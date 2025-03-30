// Pipeline Controller

module qcv_controller (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Inputs from Decoder
    input  wire        illegal_insn_i,
    input  wire        ecall_insn_i,         // v0.1 scope out
    input  wire        mret_insn_i,          // v0.1 scope out
    input  wire        dret_insn_i,          // v0.1 scope out
    input  wire        wfi_insn_i,           // v0.1 scope out
    input  wire        ebrk_insn_i,          // v0.1 scope out

    // Inputs from CSRs / Other
    input  wire        csr_pipe_flush_i,     // CSR write flush request (ignored in v0.1)
    input  wire [1:0]  priv_mode_i,          // Current privilege mode (M-mode only in v0.1)

    // Inputs from IF Stage
    input  wire        instr_valid_i,
    input  wire        instr_fetch_err_i,
    input  wire [31:0] pc_id_i,

    // Inputs from LSU
    input  wire        load_err_i,
    input  wire        store_err_i,

    // Inputs from ID Stage FSM / EX Block
    input  wire        branch_set_i,         // Branch taken signal from ID/EX FSM
    input  wire        jump_set_i,           // Jump taken signal from ID/EX FSM
    input  wire        stall_id_i,           // Stall request from ID/EX FSM

    // Outputs to IF Stage
    output wire        instr_valid_clear_o,  // Clear IF/ID register
    output wire        id_in_ready_o,        // ID stage ready for next instruction
    output wire        instr_req_o,          // Instruction fetch request
    output wire        pc_set_o,             // PC redirect signal
    output wire [1:0]  pc_mux_o,             // Next PC select
    output wire        exc_pc_mux_o,         // Exception PC select

    // Outputs to ID Stage / Other
    output wire        controller_run_o,     // ID stage execution enable (stall control)
    output wire        flush_id_o,           // Flush ID stage internal state

    // Outputs to CSRs
    output wire [6:0]  exc_cause_o,          // Exception cause code
    output wire        csr_save_if_o,        // Save IF PC to CSR
    output wire        csr_save_id_o,        // Save ID PC to CSR
    output wire        csr_restore_mret_id_o,// Restore CSRs for MRET (v0.1 scope out)
    output wire        csr_restore_dret_id_o,// Restore CSRs for DRET (v0.1 scope out)
    output wire        csr_save_cause_o,     // Save exception cause to CSR
    output wire [31:0] csr_mtval_o           // Save exception value (bad addr/instr) to CSR
);

    // --- Exception Cause Codes (subset for v0.1) ---
    localparam EXC_CAUSE_ILLEGAL_INSTRUCTION = 7'd2;
    localparam EXC_CAUSE_LOAD_ACCESS_FAULT   = 7'd5; // Includes alignment/PMP/bus error
    localparam EXC_CAUSE_STORE_ACCESS_FAULT  = 7'd7; // Includes alignment/PMP/bus error
    localparam EXC_CAUSE_INSTRUCTION_ACCESS_FAULT = 7'd1; // Fetch error

    // --- PC Mux Encodings (from IF stage) ---
    localparam PC_JUMP  = 2'b01;
    localparam PC_EXC   = 2'b10;

    // --- Exception PC Mux Encodings (from IF stage) ---
    localparam EXC_PC_EXC = 1'b0;

    // --- Internal Signals ---
    wire exception_detected; // Any exception occurred
    wire exception_in_id;    // Exception detected based on ID stage info (illegal insn)
    wire exception_in_lsu;   // Exception detected based on LSU info (load/store err)
    wire exception_in_if;    // Exception detected based on IF stage info (fetch err)

    wire take_branch;        // Branch condition met and instruction is branch
    wire take_jump;          // Instruction is jump (JAL/JALR/FENCE.I)

    wire do_flush;           // Need to flush pipeline (branch, jump, exception)
    wire do_stall;           // Need to stall pipeline

    // Use wires for combinational outputs derived from cause/mtval logic
    wire [6:0]  exc_cause_comb;
    wire [31:0] csr_mtval_comb;

    // --- Exception Detection ---
    assign exception_in_id  = illegal_insn_i; // Basic illegal instruction check
    assign exception_in_lsu = load_err_i | store_err_i; // Assumes these are valid when instr_valid_i is high
    assign exception_in_if  = instr_fetch_err_i; // Check fetch error from IF

    // Exception detected if valid instruction has an error from IF, ID, or LSU
    assign exception_detected = instr_valid_i & (exception_in_if | exception_in_id | exception_in_lsu);

    // --- Branch/Jump Detection ---
    // These signals come from the ID stage FSM/logic based on decoder and EX result
    assign take_branch = branch_set_i;
    assign take_jump   = jump_set_i;

    // --- Stall/Flush Control ---
    // Stall if ID FSM requests (stall_id_i) or if a valid instruction causes an exception
    assign do_stall = stall_id_i | exception_detected;
    // Flush if branch/jump taken or exception detected for a valid instruction
    assign do_flush = (take_branch | take_jump | exception_detected) & instr_valid_i;

    // ID stage ready signal (stall IF if ID is stalled)
    assign id_in_ready_o = ~do_stall;

    // ID stage run signal (stall ID execution if stalled)
    assign controller_run_o = ~do_stall;

    // IF/ID pipeline clear signal (clear on flush)
    assign instr_valid_clear_o = do_flush;

    // ID stage internal flush signal (flush on exception/branch/jump)
    assign flush_id_o = do_flush;

    // --- PC Control ---
    assign pc_set_o = do_flush; // Set PC on any flush condition
    assign pc_mux_o = exception_detected ? PC_EXC : PC_JUMP; // Select Exception PC or Branch/Jump Target
    assign exc_pc_mux_o = EXC_PC_EXC; // Always use mtvec base for exceptions in v0.1

    // --- Exception Cause and Value Logic (Combinational) ---
    // Determine cause and mtval based on the first detected error source
    assign exc_cause_comb = exception_in_if  ? EXC_CAUSE_INSTRUCTION_ACCESS_FAULT :
                            exception_in_id  ? EXC_CAUSE_ILLEGAL_INSTRUCTION :
                            load_err_i       ? EXC_CAUSE_LOAD_ACCESS_FAULT :
                            store_err_i      ? EXC_CAUSE_STORE_ACCESS_FAULT :
                            7'b0; // Default no exception

    // mtval: PC for fetch error, instruction for illegal, address for LSU error
    // Simplification: Use pc_id_i for all cases in v0.1 as precise faulting address/instruction might need more state
    assign csr_mtval_comb = (exception_in_if | exception_in_id | exception_in_lsu) ? pc_id_i : 32'b0;

    assign exc_cause_o = exception_detected ? exc_cause_comb : 7'b0;
    assign csr_mtval_o = exception_detected ? csr_mtval_comb : 32'b0;

    // --- CSR Save Control ---
    // Save PC to mepc, cause to mcause, value to mtval on exception
    assign csr_save_cause_o = exception_detected;
    // Save PC of the faulting instruction (pc_id_i in this stage)
    assign csr_save_id_o = exception_detected;
    assign csr_save_if_o = 1'b0; // Not saving IF PC

    // --- Other Control Signals ---
    // Instruction fetch request (simplified: always request)
    assign instr_req_o = 1'b1;

    // CSR restore signals (not implemented in v0.1)
    assign csr_restore_mret_id_o = 1'b0;
    assign csr_restore_dret_id_o = 1'b0;

endmodule : qcv_controller
