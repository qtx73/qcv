// Execute Block

module qcv_ex_block (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Inputs from ID Stage
    input  wire [3:0]  alu_operator_i,
    input  wire [31:0] alu_operand_a_i,
    input  wire [31:0] alu_operand_b_i,
    input  wire        alu_instr_first_cycle_i, // For multi-cycle ALU (unused in v0.1)

    // Outputs to ID Stage (forwarding/branch) and WB Stage
    output wire [31:0] result_ex_o,           // ALU result
    output wire [31:0] branch_target_o,       // Branch/Jump target address
    output wire        branch_decision_o,     // Branch condition result
    output wire        ex_valid_o,            // EX block result valid (always high in v0.1)

    // Output to LSU
    output wire [31:0] alu_adder_result_ex_o  // Adder result for address calculation
);

    // --- Internal Wires from ALU ---
    wire [31:0] alu_result;
    wire [31:0] alu_adder_result;
    wire        alu_comparison_result;
    wire        alu_is_equal_result; // Unused in v0.1 EX block outputs

    // --- Instantiate ALU ---
    qcv_alu u_alu (
        // Inputs from EX Block (passed from ID Stage)
        .operator_i   (alu_operator_i),
        .operand_a_i  (alu_operand_a_i),
        .operand_b_i  (alu_operand_b_i),

        // Outputs to EX Block logic
        .adder_result_o      (alu_adder_result),
        .result_o            (alu_result),
        .comparison_result_o (alu_comparison_result),
        .is_equal_result_o   (alu_is_equal_result)
        // Note: Multi-cycle and RVB ports are omitted as per v0.1 spec
    );

    // --- Output Assignments ---

    // ALU result output
    assign result_ex_o = alu_result;

    // Adder result for LSU address calculation
    assign alu_adder_result_ex_o = alu_adder_result;

    // Branch target address (calculated by ALU adder for JAL/JALR/Branch)
    assign branch_target_o = alu_adder_result;

    // Branch decision (Connects ALU comparison result as per v0.1 spec)
    // WARNING: This connection only reflects SLT/SLTU results from the ALU.
    // Proper branch condition evaluation (BEQ, BNE, etc.) based on adder_result_o
    // needs to be handled in the ID stage logic that consumes this signal.
    assign branch_decision_o = alu_comparison_result;

    // EX valid signal (always valid in single-cycle v0.1)
    assign ex_valid_o = 1'b1;

endmodule : qcv_ex_block
