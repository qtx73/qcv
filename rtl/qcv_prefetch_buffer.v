// Instruction Prefetch Buffer

module qcv_prefetch_buffer (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Control from IF Stage
    input  wire        req_i,       // Fetch request enable from IF
    input  wire        branch_i,    // Branch/Jump occurred, flush buffer
    input  wire [31:0] addr_i,      // Target address for branch/jump
    input  wire        ready_i,     // Next stage (IF/ID reg) is ready

    // Output to IF/ID Register
    output wire        valid_o,     // Output data is valid
    output wire [31:0] rdata_o,     // Fetched instruction data
    output wire [31:0] addr_o,      // Address of fetched instruction
    output wire        err_o,       // Memory error for fetched instruction

    // Interface to Instruction Memory
    output wire        instr_req_o,   // Request to instruction memory
    input  wire        instr_gnt_i,   // Grant from instruction memory
    output wire [31:0] instr_addr_o,  // Address to instruction memory
    input  wire [31:0] instr_rdata_i, // Data from instruction memory
    input  wire        instr_err_i,   // Error from instruction memory
    input  wire        instr_rvalid_i,// Valid data from instruction memory

    // Status Output
    output wire        busy_o       // Buffer is busy (waiting for memory or issuing request)
);

    localparam NUM_REQS = 2; // FIFO Depth

    // --- FIFO Registers ---
    reg [31:0] fifo_rdata_q [NUM_REQS-1:0];
    reg [31:0] fifo_addr_q  [NUM_REQS-1:0];
    reg [NUM_REQS-1:0]       fifo_err_q   ;
    reg [NUM_REQS-1:0]       fifo_valid_q ;
    reg [NUM_REQS > 1 ? 0:0] fifo_wptr_q; // Simplified for NUM_REQS=2
    reg [NUM_REQS > 1 ? 0:0] fifo_rptr_q; // Simplified for NUM_REQS=2
    reg [1:0]  fifo_cnt_q; // Count 0, 1, 2

    // --- State Registers ---
    reg [31:0] fetch_addr_q;        // Next address to fetch
    reg [31:0] stored_addr_q [NUM_REQS-1:0]; // Addresses currently requested from memory
    reg [NUM_REQS-1:0]       rdata_outstanding_q; // Request outstanding flags
    reg [NUM_REQS-1:0]       branch_discard_q;    // Discard flags due to branch

    // --- Wires / Combinational Logic ---
    wire fifo_full;
    wire fifo_empty;
    wire fifo_push;
    wire fifo_pop;
    wire [NUM_REQS > 1 ? 0:0] fifo_wptr_next; // Simplified for NUM_REQS=2
    wire [NUM_REQS > 1 ? 0:0] fifo_rptr_next; // Simplified for NUM_REQS=2
    wire [1:0] fifo_cnt_next;

    wire [31:0] fetch_addr_next;
    wire        do_fetch;
    wire        mem_req_ok;
    wire        accept_branch;
    wire        clear_outstanding;

    wire [31:0] fifo_rdata_out;
    wire [31:0] fifo_addr_out;
    wire        fifo_err_out;

    // --- Logic Implementation ---

    // FIFO Control
    assign fifo_empty = (fifo_cnt_q == 2'b00);
    assign fifo_full  = (fifo_cnt_q == NUM_REQS); // == 2'b10 for NUM_REQS=2

    assign fifo_pop = ~fifo_empty & ready_i;
    assign fifo_push = instr_rvalid_i & ~branch_discard_q[0]; // Push if valid response and not discarded

    assign fifo_wptr_next = fifo_push ? ~fifo_wptr_q : fifo_wptr_q;
    assign fifo_rptr_next = fifo_pop  ? ~fifo_rptr_q : fifo_rptr_q;

    always @(*) begin
        case ({fifo_push, fifo_pop})
            2'b00: fifo_cnt_next = fifo_cnt_q;
            2'b01: fifo_cnt_next = fifo_cnt_q - 1; // Pop
            2'b10: fifo_cnt_next = fifo_cnt_q + 1; // Push
            2'b11: fifo_cnt_next = fifo_cnt_q;     // Push and Pop
            default: fifo_cnt_next = fifo_cnt_q;
        endcase
    end

    // FIFO Data Path
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_valid_q[0] <= 1'b0;
            fifo_valid_q[1] <= 1'b0;
            fifo_wptr_q <= 1'b0;
            fifo_rptr_q <= 1'b0;
            fifo_cnt_q  <= 2'b00;
        end else begin
            fifo_wptr_q <= fifo_wptr_next;
            fifo_rptr_q <= fifo_rptr_next;
            fifo_cnt_q  <= fifo_cnt_next;

            // FIFO Write
            if (fifo_push) begin
                fifo_rdata_q[fifo_wptr_q] <= instr_rdata_i;
                fifo_addr_q[fifo_wptr_q]  <= stored_addr_q[0]; // Address corresponds to the oldest outstanding req
                fifo_err_q[fifo_wptr_q]   <= instr_err_i;
                fifo_valid_q[fifo_wptr_q] <= 1'b1;
            end

            // FIFO Read (Invalidate entry on pop)
            if (fifo_pop) begin
                fifo_valid_q[fifo_rptr_q] <= 1'b0;
            end

            // Branch Flush
            if (branch_i) begin
                fifo_valid_q[0] <= 1'b0;
                fifo_valid_q[1] <= 1'b0;
                fifo_wptr_q <= 1'b0;
                fifo_rptr_q <= 1'b0;
                fifo_cnt_q  <= 2'b00;
            end
        end
    end

    // FIFO Read Outputs
    assign fifo_rdata_out = fifo_rdata_q[fifo_rptr_q];
    assign fifo_addr_out  = fifo_addr_q[fifo_rptr_q];
    assign fifo_err_out   = fifo_err_q[fifo_rptr_q];
    assign valid_o        = fifo_valid_q[fifo_rptr_q] & ~fifo_empty; // Output valid only if entry is valid and FIFO not empty
    assign rdata_o        = fifo_rdata_out;
    assign addr_o         = fifo_addr_out;
    assign err_o          = fifo_err_out;

    // Address Logic
    assign fetch_addr_next = branch_i ? addr_i : fetch_addr_q + 32'd4;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fetch_addr_q <= 32'b0; // Or should be boot_addr? IF stage handles boot addr.
        end else begin
            // Update fetch address only when we are ready to fetch next or branching
            if (do_fetch || branch_i) begin
                 fetch_addr_q <= fetch_addr_next;
            end
        end
    end

    // Request Logic
    assign mem_req_ok = req_i & ~fifo_full & (rdata_outstanding_q[NUM_REQS-1] == 1'b0); // Can issue if enabled, FIFO not full, and last slot is free
    assign do_fetch = mem_req_ok & instr_gnt_i; // Issue request if granted

    assign instr_req_o = mem_req_ok;
    assign instr_addr_o = fetch_addr_q; // Request the current fetch address

    // Outstanding Request & Discard Logic
    assign accept_branch = branch_i;
    assign clear_outstanding = ~rst_ni | accept_branch;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rdata_outstanding_q[0] <= 1'b0;
            rdata_outstanding_q[1] <= 1'b0;
            branch_discard_q[0]    <= 1'b0;
            branch_discard_q[1]    <= 1'b0;
            stored_addr_q[0]       <= 32'b0;
            stored_addr_q[1]       <= 32'b0;
        end else begin
            // Shift register for outstanding requests
            if (instr_rvalid_i) begin // Response received for the oldest request
                rdata_outstanding_q[0] <= rdata_outstanding_q[1];
                branch_discard_q[0]    <= branch_discard_q[1];
                stored_addr_q[0]       <= stored_addr_q[1];
            end else begin // No response, keep state or shift if new req issued
                if (do_fetch) begin // Shift only if no response AND new req issued
                     rdata_outstanding_q[0] <= rdata_outstanding_q[1];
                     branch_discard_q[0]    <= branch_discard_q[1];
                     stored_addr_q[0]       <= stored_addr_q[1];
                end
                // else: Hold state if no response and no new fetch
            end

            // Handle new request issuance
            if (do_fetch) begin
                rdata_outstanding_q[1] <= 1'b1; // Mark the new slot as outstanding
                branch_discard_q[1]    <= accept_branch; // Mark for discard if branch occurred concurrently
                stored_addr_q[1]       <= fetch_addr_q; // Store the address requested
            end else begin
                 if (~instr_rvalid_i) begin // If no response, new slot remains empty unless shifted above
                     rdata_outstanding_q[1] <= rdata_outstanding_q[0] ? rdata_outstanding_q[1] : 1'b0; // Avoid overwriting shifted value
                 end else begin // Response received, new slot is cleared
                     rdata_outstanding_q[1] <= 1'b0;
                 end
                 // branch_discard_q[1] and stored_addr_q[1] retain value unless shifted or cleared by branch
            end

            // Handle branch flush
            if (accept_branch) begin
                rdata_outstanding_q[0] <= 1'b0; // Clear outstanding on branch
                rdata_outstanding_q[1] <= 1'b0;
                branch_discard_q[0]    <= 1'b1; // Mark potentially incoming responses for discard
                branch_discard_q[1]    <= 1'b1;
            end
        end
    end


    // Busy Logic
    assign busy_o = |rdata_outstanding_q | instr_req_o; // Busy if requests outstanding or trying to issue one

endmodule : qcv_prefetch_buffer
