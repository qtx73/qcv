// Instruction Fetch Stage

module qcv_if_stage (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire [31:0] boot_addr_i,
    input  wire        req_i,           // Core enable (assume high for v0.1)

    // Instruction Memory Interface (via Prefetch Buffer)
    output wire        instr_req_o,
    output wire [31:0] instr_addr_o,
    input  wire        instr_gnt_i,
    input  wire        instr_rvalid_i,
    input  wire [31:0] instr_rdata_i,
    input  wire        instr_err_i,

    // Interface to ID Stage
    output wire        instr_valid_id_o,
    output wire        instr_new_id_o,     // RVFI
    output wire [31:0] instr_rdata_id_o,
    output wire        instr_fetch_err_o,
    output wire [31:0] pc_id_o,
    input  wire        instr_valid_clear_i, // Flush IF/ID register
    input  wire        pc_set_i,            // PC redirect signal
    input  wire [1:0]  pc_mux_i,            // Next PC selector
    input  wire [0:0]  exc_pc_mux_i,        // Exception PC selector (Note: width adjusted based on usage)
    input  wire [6:0]  exc_cause,           // Exception cause (unused in v0.1 IF logic)
    input  wire [31:0] branch_target_ex_i,  // Branch/Jump target from ID/EX
    input  wire        id_in_ready_i,       // ID stage ready to accept

    // Interface to CS Registers
    input  wire [31:0] csr_mepc_i,          // mret PC (unused in v0.1)
    input  wire [31:0] csr_depc_i,          // dret PC (unused in v0.1)
    input  wire [31:0] csr_mtvec_i,         // Exception vector base
    output wire        csr_mtvec_init_o,    // mtvec init request (on reset)

    // Status Output
    output wire        if_busy_o            // IF stage busy (from prefetch buffer)
);

    // --- Parameters for PC Mux ---
    localparam PC_BOOT  = 2'b00; // Boot address
    localparam PC_JUMP  = 2'b01; // Branch / JAL / JALR target
    localparam PC_EXC   = 2'b10; // Exception handler address
    // localparam PC_ERET  = 2'b11; // MRET/DRET target (unused in v0.1)

    // --- Parameters for Exception PC Mux ---
    localparam EXC_PC_EXC = 1'b0; // mtvec based exception PC
    // localparam EXC_PC_IRQ = 1'b1; // Interrupt handler PC (unused in v0.1)

    // --- Internal Signals ---
    reg  [31:0] pc_q;             // Current Program Counter
    wire [31:0] pc_next;          // Calculated next PC value
    wire [31:0] pc_plus4;         // PC + 4

    wire [31:0] exc_pc;           // Calculated exception PC

    wire        pc_set;           // Internal PC set signal (combines external and internal flush)

    // Prefetch Buffer Interface signals
    wire        fetch_valid;
    wire [31:0] fetch_rdata;
    wire [31:0] fetch_addr;
    wire        fetch_err;
    wire        prefetch_busy;
    wire [31:0] fetch_addr_n;     // Next address requested by prefetch buffer (usually pc_next)

    // IF/ID Pipeline Registers
    reg         instr_valid_id_q;
    reg  [31:0] pc_id_q;
    reg  [31:0] instr_rdata_id_q;
    reg         instr_fetch_err_q;
    // reg         instr_new_id_q; // RVFI - Simple implementation for now

    wire        if_id_pipe_valid; // Data in IF/ID pipe is valid
    wire        if_id_pipe_ready; // IF/ID pipe can accept new data
    wire        if_id_pipe_flush; // Flush signal for IF/ID pipe

    // --- PC Logic ---
    assign pc_plus4 = pc_q + 32'd4;

    // Calculate exception handler address (simplified for v0.1)
    // Assuming non-vectored exceptions, base address from mtvec
    assign exc_pc = csr_mtvec_i; // TODO: Add mode check if needed later

    // Calculate next PC based on mux selections
    assign pc_next = pc_set_i ?
                     (pc_mux_i == PC_JUMP ? branch_target_ex_i :
                      pc_mux_i == PC_EXC  ? exc_pc :
                      pc_plus4 // Default to PC+4 for unused/boot cases in v0.1
                     ) :
                     pc_plus4; // Default increment

    // PC Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_q <= boot_addr_i;
        end else begin
            // Update PC if not stalled (implicitly handled by prefetch buffer ready)
            // or if explicitly redirected
            // The actual stall is handled by the prefetch buffer via ready_i
            // We update pc_q based on pc_next calculation which depends on pc_set_i
             pc_q <= pc_next;
        end
    end

    // --- Prefetch Buffer Instantiation ---
    // Determine the address to feed into the prefetch buffer
    assign fetch_addr_n = pc_next; // Feed the calculated next PC

    qcv_prefetch_buffer u_prefetch_buffer (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),

        // Control from IF Stage
        .req_i            (req_i),          // Core enable
        .branch_i         (pc_set_i),       // Flush on PC redirect
        .addr_i           (pc_next),        // Target address for flush/redirect
        .ready_i          (if_id_pipe_ready),// Prefetch can proceed if IF/ID pipe is ready

        // Output to IF/ID Register logic
        .valid_o          (fetch_valid),
        .rdata_o          (fetch_rdata),
        .addr_o           (fetch_addr),
        .err_o            (fetch_err),

        // Interface to Instruction Memory (pass through)
        .instr_req_o      (instr_req_o),
        .instr_gnt_i      (instr_gnt_i),
        .instr_addr_o     (instr_addr_o),
        .instr_rdata_i    (instr_rdata_i),
        .instr_err_i      (instr_err_i),
        .instr_rvalid_i   (instr_rvalid_i),

        // Status Output
        .busy_o           (prefetch_busy)
    );

    assign if_busy_o = prefetch_busy;

    // --- IF/ID Pipeline Control ---
    assign if_id_pipe_ready = id_in_ready_i; // IF/ID pipe can accept if ID stage is ready
    assign if_id_pipe_flush = instr_valid_clear_i | pc_set_i; // Flush if requested by ID or on PC redirect

    // --- IF/ID Pipeline Registers ---
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            instr_valid_id_q  <= 1'b0;
            pc_id_q           <= 32'b0;
            instr_rdata_id_q  <= 32'b0;
            instr_fetch_err_q <= 1'b0;
            // instr_new_id_q      <= 1'b0;
        end else begin
            if (if_id_pipe_flush) begin // Flush takes priority
                instr_valid_id_q <= 1'b0;
                // Keep other registers? Or clear? Let's clear for simplicity.
                pc_id_q           <= 32'b0;
                instr_rdata_id_q  <= 32'b0;
                instr_fetch_err_q <= 1'b0;
                // instr_new_id_q      <= 1'b0;
            end else if (if_id_pipe_ready) begin // If not flushing and ready, accept new data
                instr_valid_id_q  <= fetch_valid;
                // instr_new_id_q      <= fetch_valid; // Mark as new if valid data comes in
                if (fetch_valid) begin
                    pc_id_q           <= fetch_addr;
                    instr_rdata_id_q  <= fetch_rdata;
                    instr_fetch_err_q <= fetch_err;
                end else begin
                    // If fetch_valid is low, ensure instr_valid_id_q becomes 0, hold others
                    instr_valid_id_q <= 1'b0;
                end
            end
            // else: If not ready and not flushing, hold the current values
        end
    end

    // Assign outputs from pipeline registers
    assign instr_valid_id_o  = instr_valid_id_q;
    assign pc_id_o           = pc_id_q;
    assign instr_rdata_id_o  = instr_rdata_id_q;
    assign instr_fetch_err_o = instr_fetch_err_q;
    assign instr_new_id_o    = instr_valid_id_q; // Simple RVFI: new = valid in this stage

    // --- CSR MTVEC Init ---
    // Request mtvec initialization only during reset
    reg rst_req_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rst_req_q <= 1'b1;
        end else begin
            rst_req_q <= 1'b0;
        end
    end
    assign csr_mtvec_init_o = rst_req_q;

endmodule : qcv_if_stage
