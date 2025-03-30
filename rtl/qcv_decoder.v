// Instruction Decoder (Combinational)

module qcv_decoder (
    // Input from IF/ID Register
    input  wire [31:0] instr_rdata_i,

    // Outputs to Controller and ID Stage logic
    output wire        illegal_insn_o,
    output wire        ebrk_insn_o,          // v0.1 scope out
    output wire        mret_insn_o,          // v0.1 scope out
    output wire        dret_insn_o,          // v0.1 scope out
    output wire        ecall_insn_o,         // v0.1 scope out
    output wire        wfi_insn_o,           // v0.1 scope out
    output wire        jump_set_o,           // First cycle of JAL/JALR/FENCE.I
    output wire        imm_a_mux_sel_o,      // ALU OpA immediate select (mostly ZERO in v0.1)
    output wire [2:0]  imm_b_mux_sel_o,      // ALU OpB immediate select
    output wire [31:0] imm_i_type_o,
    output wire [31:0] imm_s_type_o,
    output wire [31:0] imm_b_type_o,
    output wire [31:0] imm_u_type_o,
    output wire [31:0] imm_j_type_o,
    output wire [31:0] zimm_rs1_type_o,      // Immediate for CSR access (from rs1 field)
    output wire        rf_wdata_sel_o,       // RF write data select (ALU/CSR)
    output wire        rf_we_o,              // RF write enable
    output wire [4:0]  rf_raddr_a_o,         // RF read address A (rs1)
    output wire [4:0]  rf_raddr_b_o,         // RF read address B (rs2)
    output wire [4:0]  rf_waddr_o,           // RF write address (rd)
    output wire        rf_ren_a_o,           // RF read enable A
    output wire        rf_ren_b_o,           // RF read enable B
    output wire [3:0]  alu_operator_o,       // ALU operation type
    output wire [1:0]  alu_op_a_mux_sel_o,   // ALU operand A select
    output wire        alu_op_b_mux_sel_o,   // ALU operand B select
    output wire        csr_access_o,         // CSR access instruction flag
    output wire [1:0]  csr_op_o,             // CSR operation type
    output wire        data_req_o,           // LSU memory access request
    output wire        data_we_o,            // LSU write enable
    output wire [1:0]  data_type_o,          // LSU access type
    output wire        data_sign_extension_o,// LSU load sign extension
    output wire        jump_in_dec_o,        // JAL/JALR/FENCE.I instruction flag
    output wire        branch_in_dec_o       // Branch instruction flag
);

    // --- Instruction Fields ---
    wire [6:0] opcode = instr_rdata_i[6:0];
    wire [4:0] rd     = instr_rdata_i[11:7];
    wire [2:0] funct3 = instr_rdata_i[14:12];
    wire [4:0] rs1    = instr_rdata_i[19:15];
    wire [4:0] rs2    = instr_rdata_i[24:20];
    wire [6:0] funct7 = instr_rdata_i[31:25];

    // --- Immediate Generation ---
    wire [11:0] imm_i_raw = instr_rdata_i[31:20];
    wire [11:0] imm_s_raw = {instr_rdata_i[31:25], instr_rdata_i[11:7]};
    wire [12:0] imm_b_raw = {instr_rdata_i[31], instr_rdata_i[7], instr_rdata_i[30:25], instr_rdata_i[11:8], 1'b0};
    wire [31:12] imm_u_raw = instr_rdata_i[31:12];
    wire [20:0] imm_j_raw = {instr_rdata_i[31], instr_rdata_i[19:12], instr_rdata_i[20], instr_rdata_i[30:21], 1'b0};

    // Sign extension
    assign imm_i_type_o = {{20{imm_i_raw[11]}}, imm_i_raw};
    assign imm_s_type_o = {{20{imm_s_raw[11]}}, imm_s_raw};
    assign imm_b_type_o = {{19{imm_b_raw[12]}}, imm_b_raw};
    assign imm_u_type_o = {imm_u_raw, 12'b0};
    assign imm_j_type_o = {{11{imm_j_raw[20]}}, imm_j_raw};
    // CSR immediate (zero-extended rs1 field)
    assign zimm_rs1_type_o = {27'b0, rs1};

    // --- ALU Op Encodings (from qcv_alu.v) ---
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b1000;
    localparam ALU_SLL  = 4'b0001;
    localparam ALU_SLT  = 4'b0010;
    localparam ALU_SLTU = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SRL  = 4'b0101;
    localparam ALU_SRA  = 4'b1101;
    localparam ALU_OR   = 4'b0110;
    localparam ALU_AND  = 4'b0111;
    localparam ALU_LUI  = 4'b1111; // Special case: pass imm

    // --- CSR Op Encodings ---
    localparam CSR_OP_READ  = 2'b00; // Not a real CSR op, but used internally
    localparam CSR_OP_WRITE = 2'b01;
    localparam CSR_OP_SET   = 2'b10;
    localparam CSR_OP_CLEAR = 2'b11;

    // --- Intermediate Control Signals (reg type for always block) ---
    reg        illegal_insn_int;
    reg        ebrk_insn_int;
    reg        mret_insn_int;
    reg        dret_insn_int;
    reg        ecall_insn_int;
    reg        wfi_insn_int;
    reg        jump_set_int;
    reg        imm_a_mux_sel_int;
    reg [2:0]  imm_b_mux_sel_int;
    reg        rf_wdata_sel_int;
    reg        rf_we_int;
    reg [4:0]  rf_raddr_a_int;
    reg [4:0]  rf_raddr_b_int;
    reg [4:0]  rf_waddr_int;
    reg        rf_ren_a_int;
    reg        rf_ren_b_int;
    reg [3:0]  alu_operator_int;
    reg [1:0]  alu_op_a_mux_sel_int;
    reg        alu_op_b_mux_sel_int;
    reg        csr_access_int;
    reg [1:0]  csr_op_int;
    reg        data_req_int;
    reg        data_we_int;
    reg [1:0]  data_type_int;
    reg        data_sign_extension_int;
    reg        jump_in_dec_int;
    reg        branch_in_dec_int;

    // --- Main Decode Logic ---
    always @(*) begin
        // Default values (inactive/safe state)
        illegal_insn_int        = 1'b0;
        ebrk_insn_int           = 1'b0;
        mret_insn_int           = 1'b0;
        dret_insn_int           = 1'b0;
        ecall_insn_int          = 1'b0;
        wfi_insn_int            = 1'b0;
        jump_set_int            = 1'b0;
        imm_a_mux_sel_int       = 1'b0; // Select RegA by default
        imm_b_mux_sel_int       = 3'b000; // Select RegB by default
        rf_wdata_sel_int        = 1'b0; // Select ALU result by default
        rf_we_int               = 1'b0;
        rf_raddr_a_int          = 5'b0;
        rf_raddr_b_int          = 5'b0;
        rf_waddr_int            = 5'b0;
        rf_ren_a_int            = 1'b0;
        rf_ren_b_int            = 1'b0;
        alu_operator_int        = ALU_ADD; // Default to ADD
        alu_op_a_mux_sel_int    = 2'b00; // Select RegA
        alu_op_b_mux_sel_int    = 1'b0; // Select RegB
        csr_access_int          = 1'b0;
        csr_op_int              = CSR_OP_READ; // Default
        data_req_int            = 1'b0;
        data_we_int             = 1'b0;
        data_type_int           = 2'b00; // Default Word
        data_sign_extension_int = 1'b0;
        jump_in_dec_int         = 1'b0;
        branch_in_dec_int       = 1'b0;

        // Decode based on opcode
        case (opcode)
            // --- RV32I Base ---
            7'b0110111: begin // LUI
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                alu_operator_int     = ALU_LUI; // Pass imm
                alu_op_b_mux_sel_int = 1'b1; // Select Imm
                imm_b_mux_sel_int    = 3'b011; // U-Type
            end
            7'b0010111: begin // AUIPC
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                alu_operator_int     = ALU_ADD;
                alu_op_a_mux_sel_int = 2'b01; // Select PC
                alu_op_b_mux_sel_int = 1'b1; // Select Imm
                imm_b_mux_sel_int    = 3'b011; // U-Type
            end
            7'b1101111: begin // JAL
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                alu_operator_int     = ALU_ADD; // For PC+4 link address
                alu_op_a_mux_sel_int = 2'b01; // Select PC
                alu_op_b_mux_sel_int = 1'b1; // Select Imm (ignored by ALU, used for link)
                imm_b_mux_sel_int    = 3'b100; // J-Type (Target calc in EX)
                jump_in_dec_int      = 1'b1;
                jump_set_int         = 1'b1; // Signal jump
            end
            7'b1100111: begin // JALR
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                rf_ren_a_int         = 1'b1; // Read rs1
                rf_raddr_a_int       = rs1;
                alu_operator_int     = ALU_ADD; // For PC+4 link address
                alu_op_a_mux_sel_int = 2'b01; // Select PC
                alu_op_b_mux_sel_int = 1'b1; // Select Imm (ignored by ALU, used for link)
                imm_b_mux_sel_int    = 3'b000; // I-Type (Target calc in EX uses rs1+imm)
                jump_in_dec_int      = 1'b1;
                jump_set_int         = 1'b1; // Signal jump
            end
            7'b1100011: begin // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
                rf_ren_a_int         = 1'b1; // Read rs1
                rf_raddr_a_int       = rs1;
                rf_ren_b_int         = 1'b1; // Read rs2
                rf_raddr_b_int       = rs2;
                alu_operator_int     = ALU_SUB; // Comparison uses subtraction
                alu_op_a_mux_sel_int = 2'b00; // Select RegA
                alu_op_b_mux_sel_int = 1'b0; // Select RegB
                imm_b_mux_sel_int    = 3'b010; // B-Type (Target calc in EX)
                branch_in_dec_int    = 1'b1;
                // Branch decision made in ID stage based on EX result
            end
            7'b0000011: begin // Load (LB, LH, LW, LBU, LHU)
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                rf_ren_a_int         = 1'b1; // Read rs1 (base address)
                rf_raddr_a_int       = rs1;
                alu_operator_int     = ALU_ADD; // Address calculation
                alu_op_a_mux_sel_int = 2'b00; // Select RegA
                alu_op_b_mux_sel_int = 1'b1; // Select Imm
                imm_b_mux_sel_int    = 3'b000; // I-Type
                data_req_int         = 1'b1;
                data_we_int          = 1'b0; // Load
                rf_wdata_sel_int     = 1'b1; // Select LSU result
                case (funct3)
                    3'b000: begin // LB
                        data_type_int           = 2'b01; // Byte
                        data_sign_extension_int = 1'b1;
                    end
                    3'b001: begin // LH
                        data_type_int           = 2'b10; // Half
                        data_sign_extension_int = 1'b1;
                    end
                    3'b010: begin // LW
                        data_type_int           = 2'b11; // Word
                        data_sign_extension_int = 1'b0; // N/A for word
                    end
                    3'b100: begin // LBU
                        data_type_int           = 2'b01; // Byte
                        data_sign_extension_int = 1'b0;
                    end
                    3'b101: begin // LHU
                        data_type_int           = 2'b10; // Half
                        data_sign_extension_int = 1'b0;
                    end
                    default: illegal_insn_int = 1'b1;
                endcase
            end
            7'b0100011: begin // Store (SB, SH, SW)
                rf_ren_a_int         = 1'b1; // Read rs1 (base address)
                rf_raddr_a_int       = rs1;
                rf_ren_b_int         = 1'b1; // Read rs2 (data to store)
                rf_raddr_b_int       = rs2;
                alu_operator_int     = ALU_ADD; // Address calculation
                alu_op_a_mux_sel_int = 2'b00; // Select RegA
                alu_op_b_mux_sel_int = 1'b1; // Select Imm
                imm_b_mux_sel_int    = 3'b001; // S-Type
                data_req_int         = 1'b1;
                data_we_int          = 1'b1; // Store
                case (funct3)
                    3'b000: data_type_int = 2'b01; // SB
                    3'b001: data_type_int = 2'b10; // SH
                    3'b010: data_type_int = 2'b11; // SW
                    default: illegal_insn_int = 1'b1;
                endcase
            end
            7'b0010011: begin // Immediate Arithmetic (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                rf_ren_a_int         = 1'b1; // Read rs1
                rf_raddr_a_int       = rs1;
                alu_op_a_mux_sel_int = 2'b00; // Select RegA
                alu_op_b_mux_sel_int = 1'b1; // Select Imm
                imm_b_mux_sel_int    = 3'b000; // I-Type
                case (funct3)
                    3'b000: alu_operator_int = ALU_ADD;  // ADDI
                    3'b010: alu_operator_int = ALU_SLT;  // SLTI
                    3'b011: alu_operator_int = ALU_SLTU; // SLTIU
                    3'b100: alu_operator_int = ALU_XOR;  // XORI
                    3'b110: alu_operator_int = ALU_OR;   // ORI
                    3'b111: alu_operator_int = ALU_AND;  // ANDI
                    3'b001: begin // SLLI
                        alu_operator_int = ALU_SLL;
                        // Check for illegal funct7 for RV32I (must be 0)
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    3'b101: begin // SRLI / SRAI
                        if (funct7 == 7'b0000000) alu_operator_int = ALU_SRL; // SRLI
                        else if (funct7 == 7'b0100000) alu_operator_int = ALU_SRA; // SRAI
                        else illegal_insn_int = 1'b1;
                    end
                    default: illegal_insn_int = 1'b1;
                endcase
            end
            7'b0110011: begin // Register Arithmetic (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
                rf_we_int            = 1'b1;
                rf_waddr_int         = rd;
                rf_ren_a_int         = 1'b1; // Read rs1
                rf_raddr_a_int       = rs1;
                rf_ren_b_int         = 1'b1; // Read rs2
                rf_raddr_b_int       = rs2;
                alu_op_a_mux_sel_int = 2'b00; // Select RegA
                alu_op_b_mux_sel_int = 1'b0; // Select RegB
                case (funct3)
                    3'b000: begin // ADD / SUB
                        if (funct7 == 7'b0000000) alu_operator_int = ALU_ADD; // ADD
                        else if (funct7 == 7'b0100000) alu_operator_int = ALU_SUB; // SUB
                        else illegal_insn_int = 1'b1;
                    end
                    3'b001: begin // SLL
                        alu_operator_int = ALU_SLL;
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    3'b010: begin // SLT
                        alu_operator_int = ALU_SLT;
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    3'b011: begin // SLTU
                        alu_operator_int = ALU_SLTU;
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    3'b100: begin // XOR
                        alu_operator_int = ALU_XOR;
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    3'b101: begin // SRL / SRA
                        if (funct7 == 7'b0000000) alu_operator_int = ALU_SRL; // SRL
                        else if (funct7 == 7'b0100000) alu_operator_int = ALU_SRA; // SRA
                        else illegal_insn_int = 1'b1;
                    end
                    3'b110: begin // OR
                        alu_operator_int = ALU_OR;
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    3'b111: begin // AND
                        alu_operator_int = ALU_AND;
                        if (funct7 != 7'b0000000) illegal_insn_int = 1'b1;
                    end
                    default: illegal_insn_int = 1'b1;
                endcase
            end
            7'b0001111: begin // FENCE / FENCE.I
                // Treat as NOP in v0.1 (no memory model effects implemented)
                // FENCE.I might require IF flush in full implementation
                jump_in_dec_int = (funct3 == 3'b001); // FENCE.I flag
                jump_set_int    = (funct3 == 3'b001); // Treat FENCE.I like a jump for flush
            end
            7'b1110011: begin // SYSTEM (ECALL, EBREAK, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI)
                csr_access_int = 1'b1;
                case (funct3)
                    3'b000: begin // ECALL / EBREAK / MRET / DRET / WFI
                        // Check funct12 field (instr_rdata_i[31:20])
                        casex (instr_rdata_i[31:20])
                            12'b000000000000: ecall_insn_int = 1'b1; // ECALL
                            12'b000000000001: ebrk_insn_int  = 1'b1; // EBREAK
                            12'b001100000010: mret_insn_int  = 1'b1; // MRET
                            12'b011110110010: dret_insn_int  = 1'b1; // DRET (ignore in v0.1)
                            12'b000100000101: wfi_insn_int   = 1'b1; // WFI (treat as NOP in v0.1)
                            default: illegal_insn_int = 1'b1;
                        endcase
                        // These instructions don't write to RF by default
                    end
                    3'b001: begin // CSRRW
                        rf_we_int            = (rd != 5'b0); // Write RF only if rd is not x0
                        rf_waddr_int         = rd;
                        rf_ren_a_int         = 1'b1; // Read rs1 for write data
                        rf_raddr_a_int       = rs1;
                        alu_op_a_mux_sel_int = 2'b00; // Select RegA for CSR write data
                        csr_op_int           = CSR_OP_WRITE;
                        rf_wdata_sel_int     = 1'b1; // Select CSR read result for RF write
                    end
                    3'b010: begin // CSRRS
                        rf_we_int            = (rd != 5'b0);
                        rf_waddr_int         = rd;
                        rf_ren_a_int         = (rs1 != 5'b0); // Read rs1 only if not x0
                        rf_raddr_a_int       = rs1;
                        alu_op_a_mux_sel_int = 2'b00; // Select RegA for CSR set bits
                        csr_op_int           = (rs1 == 5'b0) ? CSR_OP_READ : CSR_OP_SET; // Read if rs1=x0
                        rf_wdata_sel_int     = 1'b1; // Select CSR read result
                    end
                    3'b011: begin // CSRRC
                        rf_we_int            = (rd != 5'b0);
                        rf_waddr_int         = rd;
                        rf_ren_a_int         = (rs1 != 5'b0); // Read rs1 only if not x0
                        rf_raddr_a_int       = rs1;
                        alu_op_a_mux_sel_int = 2'b00; // Select RegA for CSR clear bits
                        csr_op_int           = (rs1 == 5'b0) ? CSR_OP_READ : CSR_OP_CLEAR; // Read if rs1=x0
                        rf_wdata_sel_int     = 1'b1; // Select CSR read result
                    end
                    3'b101: begin // CSRRWI
                        rf_we_int            = (rd != 5'b0);
                        rf_waddr_int         = rd;
                        // Use immediate for CSR write data
                        alu_op_a_mux_sel_int = 2'b10; // Select Imm (zimm_rs1)
                        imm_a_mux_sel_int    = 1'b1; // Use CSR immediate path
                        csr_op_int           = CSR_OP_WRITE;
                        rf_wdata_sel_int     = 1'b1; // Select CSR read result
                    end
                    3'b110: begin // CSRRSI
                        rf_we_int            = (rd != 5'b0);
                        rf_waddr_int         = rd;
                        // Use immediate for CSR set bits
                        alu_op_a_mux_sel_int = 2'b10; // Select Imm (zimm_rs1)
                        imm_a_mux_sel_int    = 1'b1; // Use CSR immediate path
                        csr_op_int           = (rs1 == 5'b0) ? CSR_OP_READ : CSR_OP_SET; // Read if immediate=0
                        rf_wdata_sel_int     = 1'b1; // Select CSR read result
                    end
                    3'b111: begin // CSRRCI
                        rf_we_int            = (rd != 5'b0);
                        rf_waddr_int         = rd;
                        // Use immediate for CSR clear bits
                        alu_op_a_mux_sel_int = 2'b10; // Select Imm (zimm_rs1)
                        imm_a_mux_sel_int    = 1'b1; // Use CSR immediate path
                        csr_op_int           = (rs1 == 5'b0) ? CSR_OP_READ : CSR_OP_CLEAR; // Read if immediate=0
                        rf_wdata_sel_int     = 1'b1; // Select CSR read result
                    end
                    default: illegal_insn_int = 1'b1;
                endcase
            end
            default: illegal_insn_int = 1'b1; // All other opcodes are illegal
        endcase

        // Ensure rd=x0 does not cause register write
        if (rf_waddr_int == 5'b0) begin
            rf_we_int = 1'b0;
        end

    end // always @ (*)

    // --- Assign outputs ---
    assign illegal_insn_o        = illegal_insn_int;
    assign ebrk_insn_o           = ebrk_insn_int;
    assign mret_insn_o           = mret_insn_int;
    assign dret_insn_o           = dret_insn_int;
    assign ecall_insn_o          = ecall_insn_int;
    assign wfi_insn_o            = wfi_insn_int;
    assign jump_set_o            = jump_set_int;
    assign imm_a_mux_sel_o       = imm_a_mux_sel_int;
    assign imm_b_mux_sel_o       = imm_b_mux_sel_int;
    assign rf_wdata_sel_o        = rf_wdata_sel_int;
    assign rf_we_o               = rf_we_int;
    assign rf_raddr_a_o          = rf_raddr_a_int;
    assign rf_raddr_b_o          = rf_raddr_b_int;
    assign rf_waddr_o            = rf_waddr_int;
    assign rf_ren_a_o            = rf_ren_a_int;
    assign rf_ren_b_o            = rf_ren_b_int;
    assign alu_operator_o        = alu_operator_int;
    assign alu_op_a_mux_sel_o    = alu_op_a_mux_sel_int;
    assign alu_op_b_mux_sel_o    = alu_op_b_mux_sel_int;
    assign csr_access_o          = csr_access_int;
    assign csr_op_o              = csr_op_int;
    assign data_req_o            = data_req_int;
    assign data_we_o             = data_we_int;
    assign data_type_o           = data_type_int;
    assign data_sign_extension_o = data_sign_extension_int;
    assign jump_in_dec_o         = jump_in_dec_int;
    assign branch_in_dec_o       = branch_in_dec_int;

endmodule : qcv_decoder
