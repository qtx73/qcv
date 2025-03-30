// Load Store Unit

module qcv_load_store_unit (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Data Memory Interface
    output wire        data_req_o,
    input  wire        data_gnt_i,
    input  wire        data_rvalid_i,
    input  wire        data_err_i,
    output wire [31:0] data_addr_o,
    output wire        data_we_o,
    output wire [3:0]  data_be_o,
    output wire [31:0] data_wdata_o,
    input  wire [31:0] data_rdata_i,

    // Interface from ID/EX Stage
    input  wire        lsu_we_i,             // Write enable from ID
    input  wire [1:0]  lsu_type_i,           // Access type from ID
    input  wire [31:0] lsu_wdata_i,          // Write data from ID (rs2)
    input  wire        lsu_sign_ext_i,       // Load sign extension from ID
    input  wire        lsu_req_i,            // Memory access request from ID
    input  wire [31:0] adder_result_ex_i,    // Effective address from EX

    // Interface to WB Stage
    output wire [31:0] lsu_rdata_o,          // Read data (aligned/extended)
    output wire        lsu_rdata_valid_o,    // Read data valid

    // Interface to ID Stage
    output wire        addr_incr_req_o,      // Misaligned address increment request
    output wire [31:0] addr_last_o,          // Last accessed address (for mtval)
    output wire        lsu_resp_valid_o,     // LSU response valid (done/error)
    output wire        load_err_o,           // Load error occurred
    output wire        store_err_o,          // Store error occurred

    // Status Output
    output wire        busy_o                // LSU is busy
);

    // --- FSM States ---
    localparam [1:0] FSM_IDLE      = 2'b00;
    localparam [1:0] FSM_WAIT_GNT  = 2'b01;
    localparam [1:0] FSM_WAIT_RVALID = 2'b10;
    // Add states for misaligned if needed later

    // --- Internal Registers ---
    reg [1:0]  ls_fsm_cs; // Current state
    reg [1:0]  ls_fsm_ns; // Next state

    reg [31:0] data_addr_q;      // Registered memory address
    reg [3:0]  data_be_q;        // Registered byte enable
    reg [31:0] data_wdata_q;     // Registered write data
    reg        data_we_q;        // Registered write enable
    reg        data_req_q;       // Registered memory request

    reg [1:0]  data_type_q;      // Registered access type for load result processing
    reg        data_sign_ext_q;  // Registered sign extension flag
    reg [1:0]  rdata_offset_q;   // Registered address offset for load result processing
    reg [31:0] lsu_rdata_q;      // Registered load data result
    reg        lsu_rdata_valid_int; // Internal load data valid signal
    reg        lsu_err_q;        // Registered error flag from memory response
    reg [31:0] addr_last_q;      // Registered last accessed address

    // --- Internal Wires ---
    wire [1:0] addr_offset;      // Lower 2 bits of the effective address
    wire [31:0] data_addr_w_aligned; // Word-aligned address for memory request
    wire [3:0]  data_be_calc;     // Calculated byte enable
    wire [31:0] data_wdata_aligned; // Aligned write data

    wire        is_load;
    wire        is_store;
    wire        req_valid_and_ready; // Request is valid and FSM is IDLE

    // --- Address and Data Alignment ---
    assign addr_offset = adder_result_ex_i[1:0];
    assign data_addr_w_aligned = {adder_result_ex_i[31:2], 2'b00};

    // Calculate Byte Enable based on type and offset
    assign data_be_calc = (lsu_type_i == 2'b01) ? (4'b1 << addr_offset) : // Byte
                          (lsu_type_i == 2'b10) ? (4'b11 << addr_offset) : // Half-word
                          (lsu_type_i == 2'b11) ? 4'b1111 : // Word
                          4'b0000; // Default/Illegal

    // Align Write Data (Shift data according to offset)
    assign data_wdata_aligned = lsu_wdata_i << (addr_offset * 8);

    // --- FSM Logic ---
    assign req_valid_and_ready = lsu_req_i & (ls_fsm_cs == FSM_IDLE);
    assign is_load = req_valid_and_ready & ~lsu_we_i;
    assign is_store = req_valid_and_ready & lsu_we_i;

    // Next state logic
    always @(*) begin
        ls_fsm_ns = ls_fsm_cs; // Default: stay in current state
        lsu_rdata_valid_int = 1'b0; // Default valid low
        lsu_err_q = 1'b0;         // Default error low (will be overwritten if error occurs)

        case (ls_fsm_cs)
            FSM_IDLE: begin
                if (lsu_req_i) begin
                    ls_fsm_ns = FSM_WAIT_GNT;
                end
            end
            FSM_WAIT_GNT: begin
                if (data_gnt_i) begin
                    if (data_we_q) begin // Store operation granted
                        ls_fsm_ns = FSM_IDLE; // Store completes after grant
                        lsu_err_q = data_err_i; // Latch error on grant cycle for store
                    end else begin // Load operation granted
                        ls_fsm_ns = FSM_WAIT_RVALID;
                    end
                end
            end
            FSM_WAIT_RVALID: begin // Only for loads
                if (data_rvalid_i) begin
                    ls_fsm_ns = FSM_IDLE;
                    lsu_rdata_valid_int = 1'b1; // Data is valid in this cycle
                    lsu_err_q = data_err_i;   // Latch error status
                end
            end
            default: ls_fsm_ns = FSM_IDLE;
        endcase
    end

    // FSM state register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ls_fsm_cs <= FSM_IDLE;
        end else begin
            ls_fsm_cs <= ls_fsm_ns;
        end
    end

    // --- Memory Interface Registers ---
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            data_req_q <= 1'b0;
            data_addr_q <= 32'b0;
            data_be_q <= 4'b0;
            data_wdata_q <= 32'b0;
            data_we_q <= 1'b0;
            addr_last_q <= 32'b0;
        end else begin
            // Register inputs on IDLE->WAIT_GNT transition
            if (req_valid_and_ready) begin
                data_req_q <= 1'b1; // Assert request
                data_addr_q <= data_addr_w_aligned;
                data_be_q <= data_be_calc;
                data_wdata_q <= data_wdata_aligned;
                data_we_q <= lsu_we_i;
                addr_last_q <= adder_result_ex_i; // Store the actual effective address
            end else if (ls_fsm_cs == FSM_WAIT_GNT && data_gnt_i) begin
                // Deassert request once granted
                data_req_q <= 1'b0;
            end else if (ls_fsm_cs == FSM_IDLE) begin
                 data_req_q <= 1'b0; // Ensure request is low in IDLE
            end
            // Keep other values registered until next request
        end
    end

    // Assign outputs to memory interface
    assign data_req_o   = data_req_q;
    assign data_addr_o  = data_addr_q;
    assign data_be_o    = data_be_q;
    assign data_wdata_o = data_wdata_q;
    assign data_we_o    = data_we_q;

    // --- Load Data Processing Registers ---
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            data_type_q <= 2'b0;
            data_sign_ext_q <= 1'b0;
            rdata_offset_q <= 2'b0;
        end else begin
            // Latch type/sign/offset when request is accepted
            if (req_valid_and_ready) begin
                data_type_q <= lsu_type_i;
                data_sign_ext_q <= lsu_sign_ext_i;
                rdata_offset_q <= addr_offset;
            end
        end
    end

    // --- Load Data Extraction and Extension ---
    wire [31:0] rdata_shifted = data_rdata_i >> (rdata_offset_q * 8);
    wire [15:0] rdata_half = rdata_shifted[15:0];
    wire [7:0]  rdata_byte = rdata_shifted[7:0];
    reg [31:0]  lsu_rdata_comb; // Combinational result

    always @(*) begin
        case (data_type_q)
            2'b01: begin // Byte
                lsu_rdata_comb = data_sign_ext_q ? {{24{rdata_byte[7]}}, rdata_byte} : {24'b0, rdata_byte};
            end
            2'b10: begin // Half-word
                lsu_rdata_comb = data_sign_ext_q ? {{16{rdata_half[15]}}, rdata_half} : {16'b0, rdata_half};
            end
            2'b11: begin // Word
                // Assuming memory returns aligned word, no shift needed if offset is 0
                // If memory interface guarantees word access, offset might not matter for LW
                lsu_rdata_comb = data_rdata_i;
            end
            default: lsu_rdata_comb = 32'b0; // Should not happen
        endcase
    end

    // Register the final load data when it becomes valid
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lsu_rdata_q <= 32'b0;
        end else begin
            if (lsu_rdata_valid_int) begin
                lsu_rdata_q <= lsu_rdata_comb;
            end
        end
    end


    // --- Output Assignments ---
    assign lsu_rdata_o = lsu_rdata_q;
    assign lsu_rdata_valid_o = lsu_rdata_valid_int; // Valid when FSM moves from WAIT_RVALID to IDLE

    // Response valid indicates completion (success or error)
    // Store completes on grant, Load completes on rvalid
    assign lsu_resp_valid_o = lsu_rdata_valid_int | (ls_fsm_cs == FSM_WAIT_GNT && data_gnt_i && data_we_q);

    // Error reporting - use the latched error corresponding to the response cycle
    assign load_err_o  = lsu_err_q & lsu_rdata_valid_int; // Error reported on load completion
    assign store_err_o = lsu_err_q & (ls_fsm_cs == FSM_WAIT_GNT && data_gnt_i && data_we_q);  // Error reported on store completion (grant cycle)

    // Busy signal
    assign busy_o = (ls_fsm_cs != FSM_IDLE);

    // Address signals for ID stage
    assign addr_last_o = addr_last_q;
    assign addr_incr_req_o = 1'b0; // Misaligned handling not implemented in v0.1

endmodule : qcv_load_store_unit
