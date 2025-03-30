// Arithmetic Logic Unit (ALU) - Combinational

module qcv_alu (
    // Inputs from EX Block
    input  wire [3:0]  operator_i,    // ALU operation type
    input  wire [31:0] operand_a_i,   // Operand A
    input  wire [31:0] operand_b_i,   // Operand B

    // Outputs to EX Block
    output wire [31:0] adder_result_o,      // Result of adder (for address calc, branches)
    output wire [31:0] result_o,            // Final ALU result
    output wire        comparison_result_o, // Result of comparison (for branches)
    output wire        is_equal_result_o    // Operands A and B are equal (unused in v0.1)
);

    // --- Local parameters for ALU operations ---
    // Encoding needs to match the decoder output (alu_operator_o)
    // Assuming a plausible encoding for RV32I base operations
    localparam ALU_ADD  = 4'b0000; // ADD, ADDI, AUIPC (uses adder result)
    localparam ALU_SUB  = 4'b1000; // SUB
    localparam ALU_SLL  = 4'b0001; // SLL, SLLI
    localparam ALU_SLT  = 4'b0010; // SLT, SLTI
    localparam ALU_SLTU = 4'b0011; // SLTU, SLTIU
    localparam ALU_XOR  = 4'b0100; // XOR, XORI
    localparam ALU_SRL  = 4'b0101; // SRL, SRLI
    localparam ALU_SRA  = 4'b1101; // SRA, SRAI
    localparam ALU_OR   = 4'b0110; // OR, ORI
    localparam ALU_AND  = 4'b0111; // AND, ANDI
    localparam ALU_LUI  = 4'b1111; // LUI (Pass operand B) - Placeholder, needs confirmation
    // Note: Branch comparisons (BEQ, BNE, BLT, BGE, BLTU, BGEU) use SUB result and comparison logic

    // --- Internal Wires ---
    wire [31:0] operand_b_neg;    // Negated operand B for subtraction/comparison
    wire [32:0] adder_result_ext; // Extended adder result for carry/borrow
    wire [31:0] shift_result;     // Result of shift operations
    wire [31:0] logic_result;     // Result of logical operations (AND, OR, XOR)
    wire        op_a_lt_op_b_signed; // Signed less than
    wire        op_a_lt_op_b_unsigned; // Unsigned less than

    // --- Adder/Subtractor ---
    // For SUB and comparisons, invert operand B and add 1 (via carry-in)
    assign operand_b_neg = ~operand_b_i;
    assign adder_result_ext = (operator_i == ALU_SUB || operator_i == ALU_SLT || operator_i == ALU_SLTU) ?
                              ({1'b0, operand_a_i} + {1'b0, operand_b_neg} + 33'd1) : // Subtraction/Compare
                              ({1'b0, operand_a_i} + {1'b0, operand_b_i} + 33'd0);   // Addition (ADD, ADDI, AUIPC)

    assign adder_result_o = adder_result_ext[31:0];

    // --- Shifter ---
    // Shift amount is lower 5 bits of operand B
    wire [4:0] shamt = operand_b_i[4:0];
    wire [31:0] sll_result = operand_a_i << shamt;
    wire [31:0] srl_result = operand_a_i >> shamt;
    wire [31:0] sra_result = $signed(operand_a_i) >>> shamt; // Arithmetic right shift

    assign shift_result = (operator_i == ALU_SLL) ? sll_result :
                          (operator_i == ALU_SRL) ? srl_result :
                          (operator_i == ALU_SRA) ? sra_result :
                          32'b0; // Default

    // --- Logical Operations ---
    assign logic_result = (operator_i == ALU_AND) ? (operand_a_i & operand_b_i) :
                          (operator_i == ALU_OR)  ? (operand_a_i | operand_b_i) :
                          (operator_i == ALU_XOR) ? (operand_a_i ^ operand_b_i) :
                          32'b0; // Default

    // --- Comparison Logic ---
    // SLT: Set if (operand_a < operand_b) signed
    assign op_a_lt_op_b_signed = $signed(operand_a_i) < $signed(operand_b_i);
    // SLTU: Set if (operand_a < operand_b) unsigned
    assign op_a_lt_op_b_unsigned = operand_a_i < operand_b_i;
    // EQ: Set if (operand_a == operand_b) -> adder_result is 0 for SUB
    // Check if the operation is SUB before concluding equality based on zero result.
    // The EX block should ideally select SUB for branch comparisons.
    assign is_equal_result_o = (adder_result_o == 32'b0) & (operator_i == ALU_SUB);

    // Comparison result for SLT/SLTU instructions. Branch comparison logic is handled in EX/ID.
    assign comparison_result_o = (operator_i == ALU_SLT)  ? op_a_lt_op_b_signed :
                                 (operator_i == ALU_SLTU) ? op_a_lt_op_b_unsigned :
                                 1'b0; // Default

    // --- Result MUX ---
    assign result_o = (operator_i == ALU_ADD || operator_i == ALU_SUB) ? adder_result_o : // ADD, SUB, ADDI
                      // AUIPC is typically handled by adding PC (OpA) and Imm (OpB)
                      // If decoder sets operator to ADD for AUIPC, this works.
                      (operator_i == ALU_SLL || operator_i == ALU_SRL || operator_i == ALU_SRA) ? shift_result : // Shifts
                      (operator_i == ALU_AND || operator_i == ALU_OR || operator_i == ALU_XOR) ? logic_result : // Logical ops
                      (operator_i == ALU_SLT || operator_i == ALU_SLTU) ? {31'b0, comparison_result_o} : // SLT, SLTU result is 0 or 1
                      (operator_i == ALU_LUI) ? operand_b_i : // LUI passes immediate (operand B)
                      // Default case for safety, should ideally not be hit for valid RV32I ops
                      32'b0;

endmodule : qcv_alu
