// Instruction Decode Stage

module qcv_id_stage (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Interface from IF Stage
    input  wire        instr_valid_i,
    input  wire [31:0] instr_rdata_i,
    input  wire        instr_fetch_err_i,
    input  wire [31:0] pc_id_i,
    output wire        instr_req_o,          // To IF (from Controller)
    output wire        instr_valid_clear_o,  // To IF (from Controller)
    output wire        id_in_ready_o,        // To IF (from Controller)
    output wire        pc_set_o,             // To IF (from Controller)
    output wire [1:0]  pc_mux_o,             // To IF (from Controller)
    output wire        exc_pc_mux_o,         // To IF (from Controller)

    // Interface from EX Block
    input  wire        branch_decision_i,
    input  wire        ex_valid_i,
    input  wire [31:0] result_ex_i,

    // Interface to EX Block
    output wire [3:0]  alu_operator_ex_o,
    output wire [31:0] alu_operand_a_ex_o,
    output wire [31:0] alu_operand_b_ex_o,
    output wire        instr_first_cycle_id_o, // To EX (from ID FSM)

    // Interface from LSU
    input  wire        lsu_resp_valid_i,
    input  wire        lsu_load_err_i,
    input  wire        lsu_store_err_i,

    // Interface to LSU
    output wire        lsu_req_o,
    output wire        lsu_we_o,
    output wire [1:0]  lsu_type_o,
    output wire        lsu_sign_ext_o,
    output wire [31:0] lsu_wdata_o,

    // Interface from Register File
    input  wire [31:0] rf_rdata_a_i,
    input  wire [31:0] rf_rdata_b_i,

    // Interface to Register File
    output wire [4:0]  rf_raddr_a_o,
    output wire [4:0]  rf_raddr_b_o,
    output wire        rf_ren_a_o,
    output wire        rf_ren_b_o,

    // Interface from CS Registers
    input  wire [1:0]  priv_mode_i,
    input  wire        illegal_csr_insn_i,
    input  wire [31:0] csr_rdata_i,

    // Interface to CS Registers
    output wire        csr_access_o,
    output wire [1:0]  csr_op_o,
    output wire        csr_op_en_o,          // To CSR (from Controller)
    output wire        csr_save_if_o,        // To CSR (from Controller)
    output wire        csr_save_id_o,        // To CSR (from Controller)
    output wire        csr_save_cause_o,     // To CSR (from Controller)
    output wire [31:0] csr_mtval_o,          // To CSR (from Controller)
    output wire [6:0]  exc_cause_o,          // To CSR (from Controller)

    // Interface to WB Stage
    output wire [4:0]  rf_waddr_id_o,
    output wire [31:0] rf_wdata_id_o,
    output wire        rf_we_id_o,
    output wire        en_wb_o,              // Enable WB stage
    output wire        instr_id_done_o       // Instruction processing done in ID
);

    // --- Internal Wires ---

    // Decoder Outputs
    wire        illegal_insn_dec;
    wire        ebrk_insn_dec;
    wire        mret_insn_dec;
    wire        dret_insn_dec;
    wire        ecall_insn_dec;
    wire        wfi_insn_dec;
    wire        jump_set_dec;
    wire        imm_a_mux_sel_dec;
    wire [2:0]  imm_b_mux_sel_dec;
    wire [31:0] imm_i_type_dec;
    wire [31:0] imm_s_type_dec;
    wire [31:0] imm_b_type_dec;
    wire [31:0] imm_u_type_dec;
    wire [31:0] imm_j_type_dec;
    wire [31:0] zimm_rs1_type_dec;
    wire        rf_wdata_sel_dec;
    wire        rf_we_dec;
    wire [4:0]  rf_raddr_a_dec;
    wire [4:0]  rf_raddr_b_dec;
    wire [4:0]  rf_waddr_dec;
    wire        rf_ren_a_dec;
    wire        rf_ren_b_dec;
    wire [3:0]  alu_operator_dec;
    wire [1:0]  alu_op_a_mux_sel_dec;
    wire        alu_op_b_mux_sel_dec;
    wire        csr_access_dec;
    wire [1:0]  csr_op_dec;
    wire        data_req_dec;
    wire        data_we_dec;
    wire [1:0]  data_type_dec;
    wire        data_sign_extension_dec;
    wire        jump_in_dec;
    wire        branch_in_dec;

    // Controller Outputs
    wire        controller_run;
    wire        flush_id;
    // Outputs to IF stage are directly connected from controller instance

    // Operand Mux Outputs
    wire [31:0] alu_operand_a;
    wire [31:0] alu_operand_b;
    wire [31:0] immediate; // Selected immediate for ALU operand B

    // ID/EX FSM signals
    reg         id_fsm_q; // Simplified: 0=IDLE/FIRST_CYCLE, 1=WAIT_LSU
    wire        id_fsm_next;
    wire        stall_id; // Stall request from FSM
    wire        branch_set; // Branch taken signal to controller
    wire        jump_set;   // Jump taken signal to controller
    wire        instr_executing; // Instruction is currently executing (not stalled)
    wire        instr_done;      // Instruction completed in this stage

    // WB data selection
    wire [31:0] wb_rf_wdata;
    wire        wb_rf_we;

    // --- Instantiate Decoder ---
    qcv_decoder u_decoder (
        .instr_rdata_i          (instr_rdata_i),
        .illegal_insn_o         (illegal_insn_dec),
        .ebrk_insn_o            (ebrk_insn_dec),
        .mret_insn_o            (mret_insn_dec),
        .dret_insn_o            (dret_insn_dec),
        .ecall_insn_o           (ecall_insn_dec),
        .wfi_insn_o             (wfi_insn_dec),
        .jump_set_o             (jump_set_dec),
        .imm_a_mux_sel_o        (imm_a_mux_sel_dec), // Connect if needed for OpA mux
        .imm_b_mux_sel_o        (imm_b_mux_sel_dec),
        .imm_i_type_o           (imm_i_type_dec),
        .imm_s_type_o           (imm_s_type_dec),
        .imm_b_type_o           (imm_b_type_dec),
        .imm_u_type_o           (imm_u_type_dec),
        .imm_j_type_o           (imm_j_type_dec),
        .zimm_rs1_type_o        (zimm_rs1_type_dec),
        .rf_wdata_sel_o         (rf_wdata_sel_dec),
        .rf_we_o                (rf_we_dec),
        .rf_raddr_a_o           (rf_raddr_a_dec),
        .rf_raddr_b_o           (rf_raddr_b_dec),
        .rf_waddr_o             (rf_waddr_dec),
        .rf_ren_a_o             (rf_ren_a_dec),
        .rf_ren_b_o             (rf_ren_b_dec),
        .alu_operator_o         (alu_operator_dec),
        .alu_op_a_mux_sel_o     (alu_op_a_mux_sel_dec),
        .alu_op_b_mux_sel_o     (alu_op_b_mux_sel_dec),
        .csr_access_o           (csr_access_dec),
        .csr_op_o               (csr_op_dec),
        .data_req_o             (data_req_dec),
        .data_we_o              (data_we_dec),
        .data_type_o            (data_type_dec),
        .data_sign_extension_o  (data_sign_extension_dec),
        .jump_in_dec_o          (jump_in_dec),
        .branch_in_dec_o        (branch_in_dec)
    );

    // --- Instantiate Controller ---
    qcv_controller u_controller (
        .clk_i                  (clk_i),
        .rst_ni                 (rst_ni),
        .illegal_insn_i         (illegal_insn_dec),
        .ecall_insn_i           (ecall_insn_dec),
        .mret_insn_i            (mret_insn_dec),
        .dret_insn_i            (dret_insn_dec),
        .wfi_insn_i             (wfi_insn_dec),
        .ebrk_insn_i            (ebrk_insn_dec),
        .csr_pipe_flush_i       (1'b0), // Not handled in v0.1
        .priv_mode_i            (priv_mode_i),
        .instr_valid_i          (instr_valid_i),
        .instr_fetch_err_i      (instr_fetch_err_i),
        .pc_id_i                (pc_id_i),
        .load_err_i             (lsu_load_err_i),
        .store_err_i            (lsu_store_err_i),
        .branch_set_i           (branch_set),
        .jump_set_i             (jump_set),
        .stall_id_i             (stall_id),
        // Outputs
        .instr_valid_clear_o    (instr_valid_clear_o),
        .id_in_ready_o          (id_in_ready_o),
        .controller_run_o       (controller_run),
        .instr_req_o            (instr_req_o),
        .pc_set_o               (pc_set_o),
        .pc_mux_o               (pc_mux_o),
        .exc_pc_mux_o           (exc_pc_mux_o),
        .exc_cause_o            (exc_cause_o),
        .csr_save_if_o          (csr_save_if_o),
        .csr_save_id_o          (csr_save_id_o),
        .csr_restore_mret_id_o  (), // Not used
        .csr_restore_dret_id_o  (), // Not used
        .csr_save_cause_o       (csr_save_cause_o),
        .csr_mtval_o            (csr_mtval_o),
        .flush_id_o             (flush_id)
    );

    // --- Operand Selection ---
    // Select Immediate for Operand B
    assign immediate = (imm_b_mux_sel_dec == 3'b000) ? imm_i_type_dec :
                       (imm_b_mux_sel_dec == 3'b001) ? imm_s_type_dec :
                       (imm_b_mux_sel_dec == 3'b010) ? imm_b_type_dec :
                       (imm_b_mux_sel_dec == 3'b011) ? imm_u_type_dec :
                       (imm_b_mux_sel_dec == 3'b100) ? imm_j_type_dec :
                       // CSR immediate uses a different path (imm_a_mux_sel)
                       32'b0; // Default

    // Select Operand A for ALU
    // 2'b00: RegA, 2'b01: PC, 2'b10: CSR Imm (zimm)
    assign alu_operand_a = (alu_op_a_mux_sel_dec == 2'b00) ? rf_rdata_a_i :
                           (alu_op_a_mux_sel_dec == 2'b01) ? pc_id_i :
                           (alu_op_a_mux_sel_dec == 2'b10) ? zimm_rs1_type_dec :
                           32'b0; // Default

    // Select Operand B for ALU
    // 1'b0: RegB, 1'b1: Immediate
    assign alu_operand_b = alu_op_b_mux_sel_dec ? immediate : rf_rdata_b_i;

    // --- ID/EX FSM (Simplified) ---
    // State: 0 = Idle/First Cycle, 1 = Wait LSU Response
    // Stall condition: Waiting for LSU response
    assign stall_id = id_fsm_q & ~lsu_resp_valid_i;

    // Next state logic
    assign id_fsm_next = ~id_fsm_q ? (instr_valid_i & controller_run & data_req_dec) : // Go to WAIT if valid load/store issued
                         id_fsm_q  ? (lsu_resp_valid_i | flush_id) : // Go back to IDLE if response or flush
                         1'b0; // Default stay

    // FSM register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            id_fsm_q <= 1'b0;
        end else begin
            if (flush_id) begin // Flush overrides everything
                id_fsm_q <= 1'b0;
            end else begin
                id_fsm_q <= id_fsm_next;
            end
        end
    end

    // Instruction is executing if valid, not stalled by controller, and not flushed
    assign instr_executing = instr_valid_i & controller_run & ~flush_id;

    // Instruction done condition (simplified)
    // Done if executing and it's not a multi-cycle op waiting (like LSU)
    assign instr_done = instr_executing & (~data_req_dec | lsu_resp_valid_i);

    // --- Branch/Jump Logic ---
    // Branch condition evaluation (simplified for v0.1)
    // Assumes EX block provides comparison result directly for branches
    // Need to check specific branch type from decoder (funct3)
    wire branch_cond_met;
    // This logic needs refinement based on how branch_decision_i is truly generated in EX.
    // Assuming branch_decision_i = 1 if (rs1 < rs2) for signed/unsigned based on ALU op.
    // And assuming EX block performs SUB for BEQ/BNE and result_ex_i==0 indicates equality.
    assign branch_cond_met = (branch_in_dec &
                             ((funct3 == 3'b000 & (result_ex_i == 32'b0)) | // BEQ (Check if SUB result is zero)
                              (funct3 == 3'b001 & (result_ex_i != 32'b0)) | // BNE (Check if SUB result is non-zero)
                              (funct3 == 3'b100 & branch_decision_i) | // BLT (Assume branch_decision_i is (rs1 < rs2) signed)
                              (funct3 == 3'b101 & ~branch_decision_i)| // BGE (Assume branch_decision_i is (rs1 < rs2) signed)
                              (funct3 == 3'b110 & branch_decision_i) | // BLTU (Assume branch_decision_i is (rs1 < rs2) unsigned)
                              (funct3 == 3'b111 & ~branch_decision_i)  // BGEU (Assume branch_decision_i is (rs1 < rs2) unsigned)
                             ));

    assign branch_set = instr_executing & branch_cond_met;
    assign jump_set   = instr_executing & jump_in_dec; // JAL, JALR, FENCE.I

    // --- Interface Connections ---

    // To EX Block
    assign alu_operator_ex_o    = alu_operator_dec;
    assign alu_operand_a_ex_o   = alu_operand_a;
    assign alu_operand_b_ex_o   = alu_operand_b;
    assign instr_first_cycle_id_o = ~id_fsm_q; // First cycle if FSM is in state 0

    // To LSU
    assign lsu_req_o      = instr_executing & data_req_dec & ~id_fsm_q; // Request only on first cycle if executing
    assign lsu_we_o       = data_we_dec;
    assign lsu_type_o     = data_type_dec;
    assign lsu_sign_ext_o = data_sign_extension_dec;
    assign lsu_wdata_o    = rf_rdata_b_i; // Store data comes from rs2

    // To Register File (Read)
    assign rf_raddr_a_o = rf_raddr_a_dec;
    assign rf_raddr_b_o = rf_raddr_b_dec;
    assign rf_ren_a_o   = instr_valid_i & controller_run & rf_ren_a_dec; // Enable read only if executing
    assign rf_ren_b_o   = instr_valid_i & controller_run & rf_ren_b_dec;

    // To CS Registers
    assign csr_access_o = instr_executing & csr_access_dec;
    assign csr_op_o     = csr_op_dec;
    assign csr_op_en_o  = instr_executing; // Enable CSR op if instruction is executing

    // To WB Stage
    // Select write data source for non-LSU instructions (ALU result or CSR read data)
    assign wb_rf_wdata = rf_wdata_sel_dec ? csr_rdata_i : result_ex_i;
    // Final write data and enable are selected in the WB stage based on LSU response
    assign rf_wdata_id_o = wb_rf_wdata; // Pass ALU/CSR result to WB stage
    assign rf_waddr_id_o = rf_waddr_dec;
    // Write enable for non-LSU operations
    assign rf_we_id_o    = instr_done & rf_we_dec & ~data_req_dec;
    assign en_wb_o       = instr_done; // Signal WB stage when instruction completes here
    assign instr_id_done_o = instr_done;

endmodule : qcv_id_stage
