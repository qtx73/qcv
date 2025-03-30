// QCV RV32I Core Top Level

module qcv_rv32i_core (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [31:0] hart_id_i,
    input  wire [31:0] boot_addr_i,

    // Instruction Memory Interface
    output wire        instr_req_o,
    input  wire        instr_gnt_i,
    input  wire        instr_rvalid_i,
    output wire [31:0] instr_addr_o,
    input  wire [31:0] instr_rdata_i,
    input  wire        instr_err_i,

    // Data Memory Interface
    output wire        data_req_o,
    input  wire        data_gnt_i,
    input  wire        data_rvalid_i,
    output wire        data_we_o,
    output wire [3:0]  data_be_o,
    output wire [31:0] data_addr_o,
    output wire [31:0] data_wdata_o,
    input  wire [31:0] data_rdata_i,
    input  wire        data_err_i,

    // Interrupt Inputs (v0.1 scope out, for future connection)
    // input  wire        irq_software_i,
    // input  wire        irq_timer_i,
    // input  wire        irq_external_i,
    // input  wire [15:0] irq_fast_i,
    // input  wire        irq_nm_i,

    // Interrupt Output
    output wire        irq_pending_o,

    // CPU Status Output
    output wire        core_busy_o
);

    // --- Internal Wires ---

    // IF Stage <-> ID Stage
    wire        if_instr_valid_id;
    wire        if_instr_new_id;
    wire [31:0] if_instr_rdata_id;
    wire        if_instr_fetch_err;
    wire [31:0] if_pc_id;
    wire        id_instr_req;          // To IF (from Controller in ID)
    wire        id_instr_valid_clear;  // To IF (from Controller in ID)
    wire        id_ready_if;           // To IF (from Controller in ID)
    wire        id_pc_set;             // To IF (from Controller in ID)
    wire [1:0]  id_pc_mux;             // To IF (from Controller in ID)
    wire        id_exc_pc_mux;         // To IF (from Controller in ID)
    // wire [31:0] id_branch_target_ex; // Replaced by ex_branch_target

    // ID Stage <-> EX Block
    wire [3:0]  id_alu_operator_ex;
    wire [31:0] id_alu_operand_a_ex;
    wire [31:0] id_alu_operand_b_ex;
    wire        id_instr_first_cycle;
    wire        ex_branch_decision;
    wire        ex_valid;
    wire [31:0] ex_result;
    wire [31:0] ex_branch_target;      // Branch target calculated in EX

    // ID Stage <-> LSU
    wire        id_lsu_req;
    wire        id_lsu_we;
    wire [1:0]  id_lsu_type;
    wire        id_lsu_sign_ext;
    wire [31:0] id_lsu_wdata;
    wire        lsu_resp_valid;
    wire        lsu_load_err;
    wire        lsu_store_err;
    wire [31:0] lsu_rdata;             // To WB
    wire        lsu_rdata_valid;       // To WB
    wire        lsu_addr_incr_req;     // To ID (unused v0.1)
    wire [31:0] lsu_addr_last;         // To ID (for mtval) - LSU needs to output this
    wire        lsu_busy;

    // EX Block <-> LSU
    wire [31:0] ex_alu_adder_result;   // To LSU

    // ID Stage <-> Register File
    wire [4:0]  id_rf_raddr_a;
    wire [4:0]  id_rf_raddr_b;
    wire        id_rf_ren_a;
    wire        id_rf_ren_b;
    wire [31:0] rf_rdata_a;
    wire [31:0] rf_rdata_b;

    // ID Stage <-> WB Stage
    wire [4:0]  id_rf_waddr;
    wire [31:0] id_rf_wdata;           // ALU/CSR result
    wire        id_rf_we;              // ALU/CSR write enable
    wire        id_en_wb;
    wire        id_instr_done;

    // LSU <-> WB Stage
    // lsu_rdata, lsu_rdata_valid used directly

    // WB Stage <-> Register File
    wire [4:0]  wb_rf_waddr;
    wire [31:0] wb_rf_wdata;
    wire        wb_rf_we;

    // ID Stage <-> CSR
    wire        id_csr_access;
    wire [1:0]  id_csr_op;
    wire        id_csr_op_en;
    wire        id_csr_save_if;
    wire        id_csr_save_id;
    wire        id_csr_save_cause;
    wire [31:0] id_csr_mtval;
    wire [6:0]  id_exc_cause;
    wire [1:0]  csr_priv_mode_id;
    wire        csr_illegal_insn;
    wire [31:0] csr_rdata;

    // IF Stage <-> CSR
    wire [31:0] csr_mepc;
    wire [31:0] csr_mtvec;
    wire        if_csr_mtvec_init;

    // CSR Outputs
    wire [1:0]  csr_priv_mode_lsu; // To LSU (via ID?) - Connect to ID for now
    // wire        csr_irq_pending; // Connect to top level irq_pending_o

    // IF Stage Status
    wire        if_busy;

    // --- Instantiate Modules ---

    // Instruction Fetch Stage
    qcv_if_stage u_if_stage (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        .boot_addr_i          (boot_addr_i),
        .req_i                (1'b1), // Core enable - simplified
        // Memory Interface
        .instr_req_o          (instr_req_o),
        .instr_addr_o         (instr_addr_o),
        .instr_gnt_i          (instr_gnt_i),
        .instr_rvalid_i       (instr_rvalid_i),
        .instr_rdata_i        (instr_rdata_i),
        .instr_err_i          (instr_err_i),
        // To ID Stage
        .instr_valid_id_o     (if_instr_valid_id),
        .instr_new_id_o       (if_instr_new_id), // RVFI
        .instr_rdata_id_o     (if_instr_rdata_id),
        .instr_fetch_err_o    (if_instr_fetch_err),
        .pc_id_o              (if_pc_id),
        // From ID Stage (Controller)
        .instr_valid_clear_i  (id_instr_valid_clear),
        .pc_set_i             (id_pc_set),
        .pc_mux_i             (id_pc_mux),
        .exc_pc_mux_i         (id_exc_pc_mux),
        .exc_cause            (), // Not used directly by IF
        .branch_target_ex_i   (ex_branch_target), // Target comes from EX block
        .id_in_ready_i        (id_ready_if),
        // From CSR
        .csr_mepc_i           (csr_mepc),
        .csr_depc_i           (32'b0), // Unused v0.1
        .csr_mtvec_i          (csr_mtvec),
        // To CSR
        .csr_mtvec_init_o     (if_csr_mtvec_init),
        // Status
        .if_busy_o            (if_busy)
    );

    // Instruction Decode Stage
    qcv_id_stage u_id_stage (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        // From IF Stage
        .instr_valid_i        (if_instr_valid_id),
        .instr_rdata_i        (if_instr_rdata_id),
        .instr_fetch_err_i    (if_instr_fetch_err),
        .pc_id_i              (if_pc_id),
        // To IF Stage (Controller)
        .instr_req_o          (id_instr_req),
        .instr_valid_clear_o  (id_instr_valid_clear),
        .id_in_ready_o        (id_ready_if),
        .pc_set_o             (id_pc_set),
        .pc_mux_o             (id_pc_mux),
        .exc_pc_mux_o         (id_exc_pc_mux),
        // From EX Block
        .branch_decision_i    (ex_branch_decision),
        .ex_valid_i           (ex_valid),
        .result_ex_i          (ex_result),
        // To EX Block
        .alu_operator_ex_o    (id_alu_operator_ex),
        .alu_operand_a_ex_o   (id_alu_operand_a_ex),
        .alu_operand_b_ex_o   (id_alu_operand_b_ex),
        .instr_first_cycle_id_o(id_instr_first_cycle),
        // From LSU
        .lsu_resp_valid_i     (lsu_resp_valid),
        .lsu_load_err_i       (lsu_load_err),
        .lsu_store_err_i      (lsu_store_err),
        // To LSU
        .lsu_req_o            (id_lsu_req),
        .lsu_we_o             (id_lsu_we),
        .lsu_type_o           (id_lsu_type),
        .lsu_sign_ext_o       (id_lsu_sign_ext),
        .lsu_wdata_o          (id_lsu_wdata),
        // From Register File
        .rf_rdata_a_i         (rf_rdata_a),
        .rf_rdata_b_i         (rf_rdata_b),
        // To Register File
        .rf_raddr_a_o         (id_rf_raddr_a),
        .rf_raddr_b_o         (id_rf_raddr_b),
        .rf_ren_a_o           (id_rf_ren_a),
        .rf_ren_b_o           (id_rf_ren_b),
        // From CS Registers
        .priv_mode_i          (csr_priv_mode_id),
        .illegal_csr_insn_i   (csr_illegal_insn),
        .csr_rdata_i          (csr_rdata),
        // To CS Registers
        .csr_access_o         (id_csr_access),
        .csr_op_o             (id_csr_op),
        .csr_op_en_o          (id_csr_op_en),
        .csr_save_if_o        (id_csr_save_if),
        .csr_save_id_o        (id_csr_save_id),
        .csr_save_cause_o     (id_csr_save_cause),
        .csr_mtval_o          (id_csr_mtval), // Pass mtval calculated in ID controller
        .exc_cause_o          (id_exc_cause), // Pass cause calculated in ID controller
        // To WB Stage
        .rf_waddr_id_o        (id_rf_waddr),
        .rf_wdata_id_o        (id_rf_wdata),
        .rf_we_id_o           (id_rf_we),
        .en_wb_o              (id_en_wb),
        .instr_id_done_o      (id_instr_done)
    );

    // Execute Block
    qcv_ex_block u_ex_block (
        .clk_i                  (clk_i),
        .rst_ni                 (rst_ni),
        // From ID Stage
        .alu_operator_i         (id_alu_operator_ex),
        .alu_operand_a_i        (id_alu_operand_a_ex),
        .alu_operand_b_i        (id_alu_operand_b_ex),
        .alu_instr_first_cycle_i(id_instr_first_cycle),
        // To ID Stage
        .result_ex_o            (ex_result),
        .branch_target_o        (ex_branch_target),
        .branch_decision_o      (ex_branch_decision),
        .ex_valid_o             (ex_valid),
        // To LSU
        .alu_adder_result_ex_o  (ex_alu_adder_result)
    );

    // Load Store Unit
    qcv_load_store_unit u_lsu (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        // Data Memory Interface
        .data_req_o           (data_req_o),
        .data_gnt_i           (data_gnt_i),
        .data_rvalid_i        (data_rvalid_i),
        .data_err_i           (data_err_i),
        .data_addr_o          (data_addr_o),
        .data_we_o            (data_we_o),
        .data_be_o            (data_be_o),
        .data_wdata_o         (data_wdata_o),
        .data_rdata_i         (data_rdata_i),
        // From ID/EX Stage
        .lsu_we_i             (id_lsu_we),
        .lsu_type_i           (id_lsu_type),
        .lsu_wdata_i          (rf_rdata_b), // Store data comes from RF read B
        .lsu_sign_ext_i       (id_lsu_sign_ext),
        .lsu_req_i            (id_lsu_req),
        .adder_result_ex_i    (ex_alu_adder_result), // Effective address from EX
        // To WB Stage
        .lsu_rdata_o          (lsu_rdata),
        .lsu_rdata_valid_o    (lsu_rdata_valid),
        // To ID Stage
        .addr_incr_req_o      (lsu_addr_incr_req), // Unused v0.1
        .addr_last_o          (lsu_addr_last),     // To ID for mtval
        .lsu_resp_valid_o     (lsu_resp_valid),
        .load_err_o           (lsu_load_err),
        .store_err_o          (lsu_store_err),
        // Status
        .busy_o               (lsu_busy)
    );

    // Write Back Stage
    qcv_wb u_wb_stage (
        .clk_i              (clk_i), // Unused
        .rst_ni             (rst_ni), // Unused
        // From ID Stage
        .en_wb_i            (id_en_wb),
        .rf_waddr_id_i      (id_rf_waddr),
        .rf_wdata_id_i      (id_rf_wdata), // ALU/CSR result
        .rf_we_id_i         (id_rf_we),    // ALU/CSR write enable
        // From LSU
        .rf_wdata_lsu_i     (lsu_rdata),
        .rf_we_lsu_i        (lsu_rdata_valid & ~lsu_load_err), // LSU write enable (only if valid load without error)
        .lsu_resp_valid_i   (lsu_resp_valid), // Unused
        .lsu_resp_err_i     (lsu_load_err | lsu_store_err), // Unused
        // To Register File
        .rf_waddr_wb_o      (wb_rf_waddr),
        .rf_wdata_wb_o      (wb_rf_wdata),
        .rf_we_wb_o         (wb_rf_we)
    );

    // Register File
    qcv_register_file_ff u_register_file (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        // Read Port A (rs1)
        .raddr_a_i    (id_rf_raddr_a),
        .rdata_a_o    (rf_rdata_a),
        // Read Port B (rs2)
        .raddr_b_i    (id_rf_raddr_b),
        .rdata_b_o    (rf_rdata_b),
        // Write Port A (rd) from WB Stage
        .waddr_a_i    (wb_rf_waddr),
        .wdata_a_i    (wb_rf_wdata),
        .we_a_i       (wb_rf_we)
        // Read enables (id_rf_ren_a/b) are inputs to ID stage logic, not RF
    );

    // Control and Status Registers
    qcv_cs_registers u_cs_registers (
        .clk_i                (clk_i),
        .rst_ni               (rst_ni),
        .hart_id_i            (hart_id_i),
        .csr_mtvec_init_i     (if_csr_mtvec_init),
        .boot_addr_i          (boot_addr_i),
        // From ID Stage
        .csr_access_i         (id_csr_access),
        .csr_addr_i           (if_instr_rdata_id[31:20]), // CSR address from instruction in ID
        .csr_wdata_i          (id_alu_operand_a_ex), // Write data comes from OpA (rs1/imm)
        .csr_op_i             (id_csr_op),
        .csr_op_en_i          (id_csr_op_en),
        .pc_if_i              (if_pc_id), // Pass ID PC for exception saving
        .pc_id_i              (if_pc_id),
        .csr_save_if_i        (id_csr_save_if),
        .csr_save_id_i        (id_csr_save_id),
        .csr_save_cause_i     (id_csr_save_cause),
        .csr_mcause_i         (id_exc_cause), // Cause from ID controller
        .csr_mtval_i          (id_csr_mtval), // Value from ID controller (or LSU via ID?) - Needs clarification on mtval source for LSU errors
        // To ID Stage
        .priv_mode_id_o       (csr_priv_mode_id),
        .priv_mode_lsu_o      (csr_priv_mode_lsu), // Connect to ID for now
        .csr_rdata_o          (csr_rdata),
        .illegal_csr_insn_o   (csr_illegal_insn),
        // To IF Stage
        .csr_mtvec_o          (csr_mtvec),
        .csr_mepc_o           (csr_mepc)
        // Interrupt pending output needed
        // .irq_pending_o      (csr_irq_pending)
    );

    // --- Top Level Outputs ---
    // Busy signal (simplified: busy if IF or LSU is busy)
    assign core_busy_o = if_busy | lsu_busy;

    // Interrupt pending (stub for v0.1)
    assign irq_pending_o = 1'b0; // Connect to csr_irq_pending when implemented

endmodule : qcv_rv32i_core
