// Control and Status Registers (CSRs)

module qcv_cs_registers (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Inputs
    input  wire [31:0] hart_id_i,          // Hart ID (for mhartid)
    input  wire        csr_mtvec_init_i,   // mtvec initialization request
    input  wire [31:0] boot_addr_i,        // Boot address (for mtvec init)
    input  wire        csr_access_i,       // CSR access request from ID
    input  wire [11:0] csr_addr_i,         // CSR address from ID
    input  wire [31:0] csr_wdata_i,        // Write data from ID
    input  wire [1:0]  csr_op_i,           // CSR operation type from ID
    input  wire        csr_op_en_i,        // CSR operation enable from ID
    input  wire [31:0] pc_if_i,            // PC from IF (for exception save)
    input  wire [31:0] pc_id_i,            // PC from ID (for exception save)
    input  wire        csr_save_if_i,      // Save IF PC on exception
    input  wire        csr_save_id_i,      // Save ID PC on exception
    input  wire        csr_save_cause_i,   // Save cause on exception
    input  wire [6:0]  csr_mcause_i,       // Exception cause code from Controller
    input  wire [31:0] csr_mtval_i,        // Exception value from Controller

    // Outputs
    output wire [1:0]  priv_mode_id_o,     // Current privilege mode to ID (M-mode in v0.1)
    output wire [1:0]  priv_mode_lsu_o,    // Current privilege mode to LSU (M-mode in v0.1)
    output wire [31:0] csr_mtvec_o,        // Exception vector base address to IF
    output wire [31:0] csr_rdata_o,        // Read data to ID
    output wire [31:0] csr_mepc_o,         // Exception return address to IF
    output wire        illegal_csr_insn_o  // Illegal CSR access error to ID
);

    // --- CSR Address Map (Subset for v0.1) ---
    localparam CSR_MSTATUS  = 12'h300;
    localparam CSR_MISA     = 12'h301;
    localparam CSR_MIE      = 12'h304; // Read/Write stub
    localparam CSR_MTVEC    = 12'h305;
    localparam CSR_MSCRATCH = 12'h340;
    localparam CSR_MEPC     = 12'h341;
    localparam CSR_MCAUSE   = 12'h342;
    localparam CSR_MTVAL    = 12'h343;
    localparam CSR_MIP      = 12'h344; // Read/Write stub
    localparam CSR_MHARTID  = 12'hF14; // Read Only

    // --- CSR Operation Types (from ID Stage) ---
    localparam CSR_OP_READ  = 2'b00; // Used internally for read-only ops
    localparam CSR_OP_WRITE = 2'b01;
    localparam CSR_OP_SET   = 2'b10;
    localparam CSR_OP_CLEAR = 2'b11;

    // --- Privilege Levels ---
    localparam PRIV_LVL_M = 2'b11;

    // --- MISA Register Value (RV32I) ---
    // 31-30: MXL=1 (32-bit)
    // 25-0 : Extensions (I=1)
    localparam MISA_VALUE = 32'h40000100; // RV32I (I extension bit 8)

    // --- Internal CSR Registers ---
    reg [31:0] mstatus_q;
    reg [31:0] mie_q;     // Stub for v0.1
    reg [31:0] mip_q;     // Stub for v0.1
    reg [31:0] mtvec_q;
    reg [31:0] mscratch_q;
    reg [31:0] mepc_q;
    reg [31:0] mcause_q;
    reg [31:0] mtval_q;
    reg [1:0]  priv_lvl_q; // Current privilege level

    // --- Wires for Read/Write Logic ---
    wire [31:0] csr_read_data;    // Data read from selected CSR
    wire [31:0] csr_write_data;   // Data to be written (after op calculation)
    wire        csr_write_enable; // Final write enable for the selected CSR
    wire        illegal_csr_addr; // Address is not implemented or reserved
    wire        illegal_csr_write;// Write attempt to read-only CSR
    wire        illegal_csr_priv; // Access requires higher privilege

    // --- CSR Read Logic ---
    assign csr_read_data =
        (csr_addr_i == CSR_MSTATUS)  ? mstatus_q  :
        (csr_addr_i == CSR_MISA)     ? MISA_VALUE :
        (csr_addr_i == CSR_MIE)      ? mie_q      : // Stub read
        (csr_addr_i == CSR_MTVEC)    ? mtvec_q    :
        (csr_addr_i == CSR_MSCRATCH) ? mscratch_q :
        (csr_addr_i == CSR_MEPC)     ? mepc_q     :
        (csr_addr_i == CSR_MCAUSE)   ? mcause_q   :
        (csr_addr_i == CSR_MTVAL)    ? mtval_q    :
        (csr_addr_i == CSR_MIP)      ? mip_q      : // Stub read
        (csr_addr_i == CSR_MHARTID)  ? hart_id_i  :
        32'b0; // Default for unimplemented/illegal

    // --- CSR Write Data Calculation ---
    assign csr_write_data =
        (csr_op_i == CSR_OP_WRITE) ? csr_wdata_i :
        (csr_op_i == CSR_OP_SET)   ? (csr_read_data | csr_wdata_i) :
        (csr_op_i == CSR_OP_CLEAR) ? (csr_read_data & ~csr_wdata_i) :
        csr_read_data; // Default for READ op

    // --- Legality Checks ---
    // Check if the address is valid and writable in v0.1 M-mode
    assign illegal_csr_addr = ~((csr_addr_i == CSR_MSTATUS)  ||
                                (csr_addr_i == CSR_MISA)     || // RO check below
                                (csr_addr_i == CSR_MIE)      || // RW Stub
                                (csr_addr_i == CSR_MTVEC)    ||
                                (csr_addr_i == CSR_MSCRATCH) ||
                                (csr_addr_i == CSR_MEPC)     ||
                                (csr_addr_i == CSR_MCAUSE)   ||
                                (csr_addr_i == CSR_MTVAL)    ||
                                (csr_addr_i == CSR_MIP)      || // RW Stub
                                (csr_addr_i == CSR_MHARTID));    // RO check below

    // Check for writes to Read-Only CSRs
    assign illegal_csr_write = (csr_op_i != CSR_OP_READ) &
                               ((csr_addr_i == CSR_MISA) || (csr_addr_i == CSR_MHARTID));

    // Privilege check (simplified: always allow in M-mode v0.1)
    assign illegal_csr_priv = 1'b0; // Assume M-mode always

    // Final illegal instruction signal
    assign illegal_csr_insn_o = csr_access_i & (illegal_csr_addr | illegal_csr_write | illegal_csr_priv);

    // Final write enable signal
    assign csr_write_enable = csr_access_i & csr_op_en_i & (csr_op_i != CSR_OP_READ) & ~illegal_csr_insn_o;

    // --- CSR Register Updates ---
    wire mstatus_en = csr_write_enable & (csr_addr_i == CSR_MSTATUS);
    wire mie_en     = csr_write_enable & (csr_addr_i == CSR_MIE);
    wire mip_en     = csr_write_enable & (csr_addr_i == CSR_MIP);
    wire mtvec_en   = csr_write_enable & (csr_addr_i == CSR_MTVEC);
    wire mscratch_en= csr_write_enable & (csr_addr_i == CSR_MSCRATCH);
    wire mepc_en    = csr_write_enable & (csr_addr_i == CSR_MEPC);
    wire mcause_en  = csr_write_enable & (csr_addr_i == CSR_MCAUSE);
    wire mtval_en   = csr_write_enable & (csr_addr_i == CSR_MTVAL);

    // Exception save signals
    wire save_on_exception = csr_save_cause_i; // Trigger for saving state
    wire [31:0] pc_to_save = csr_save_id_i ? pc_id_i : pc_if_i; // Select which PC to save

    // MSTATUS fields (simplified for v0.1)
    localparam MSTATUS_MIE_BIT = 3;
    localparam MSTATUS_MPIE_BIT = 7;
    localparam MSTATUS_MPP_BIT_HI = 12;
    localparam MSTATUS_MPP_BIT_LO = 11;

    wire mstatus_mie = mstatus_q[MSTATUS_MIE_BIT];
    wire [1:0] mstatus_mpp = mstatus_q[MSTATUS_MPP_BIT_HI:MSTATUS_MPP_BIT_LO];

    // Calculate next mstatus value
    wire [31:0] mstatus_next_write = csr_write_data; // TODO: Add masking for read-only/WARL bits
    wire [31:0] mstatus_next_exception;
    assign mstatus_next_exception = {mstatus_q[31:MSTATUS_MPP_BIT_HI+1],
                                     priv_lvl_q, // MPP gets current privilege level
                                     mstatus_q[MSTATUS_MPP_BIT_LO-1:MSTATUS_MPIE_BIT+1],
                                     mstatus_mie, // MPIE gets current MIE
                                     mstatus_q[MSTATUS_MPIE_BIT-1:MSTATUS_MIE_BIT+1],
                                     1'b0, // MIE gets cleared
                                     mstatus_q[MSTATUS_MIE_BIT-1:0]};

    // MSTATUS Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mstatus_q <= 32'b0; // Reset value
            priv_lvl_q <= PRIV_LVL_M; // Start in M-mode
        end else begin
            if (save_on_exception) begin
                mstatus_q <= mstatus_next_exception;
                priv_lvl_q <= PRIV_LVL_M; // Enter M-mode on exception
            end else if (mstatus_en) begin
                // Apply WARL behavior (Write Any Read Legal) - simplified: allow write
                mstatus_q <= mstatus_next_write;
                // Update privilege level if MPP is written? Not for v0.1 (no MRET)
            end
            // Handle MRET later if needed: priv_lvl_q <= mstatus_mpp; mstatus_q[MSTATUS_MIE_BIT] <= mstatus_q[MSTATUS_MPIE_BIT]; etc.
        end
    end

    // MIE Register (Stub)
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mie_q <= 32'b0;
        end else if (mie_en) begin
            mie_q <= csr_write_data; // Allow write for stub
        end
    end

    // MIP Register (Stub)
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mip_q <= 32'b0;
        end else if (mip_en) begin
            // Typically read-only or has W1C bits, simplified RW stub for v0.1
            mip_q <= csr_write_data;
        end
        // TODO: Connect actual interrupt inputs later
    end

    // MTVEC Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mtvec_q <= 32'b0; // Default reset
        end else if (csr_mtvec_init_i) begin
             // Initialize based on boot address (base only, mode=Direct)
             mtvec_q <= {boot_addr_i[31:2], 2'b00}; // Mode = Direct
        end else if (mtvec_en) begin
            // Allow writing base and mode (mode bits are low 2 bits)
            // Mode must be 0 (Direct) or 1 (Vectored)
            mtvec_q <= {csr_write_data[31:2], csr_write_data[1:0] & 2'b01};
        end
    end

    // MSCRATCH Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mscratch_q <= 32'b0;
        end else if (mscratch_en) begin
            mscratch_q <= csr_write_data;
        end
    end

    // MEPC Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mepc_q <= 32'b0;
        end else if (save_on_exception) begin
            mepc_q <= {pc_to_save[31:1], 1'b0}; // Save PC (aligned to 2 bytes)
        end else if (mepc_en) begin
            mepc_q <= {csr_write_data[31:1], 1'b0}; // Write aligned PC
        end
    end

    // MCAUSE Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mcause_q <= 32'b0;
        end else if (save_on_exception) begin
            // Bit 31 = Interrupt (0 for exceptions), Bits 6:0 = Cause code
            mcause_q <= {1'b0, 24'b0, csr_mcause_i};
        end else if (mcause_en) begin
            // Allow write? Check spec. Usually only on exception. Let's allow for now.
            mcause_q <= csr_write_data;
        end
    end

    // MTVAL Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mtval_q <= 32'b0;
        end else if (save_on_exception) begin
            mtval_q <= csr_mtval_i; // Value provided by controller
        end else if (mtval_en) begin
            mtval_q <= csr_write_data;
        end
    end

    // --- Assign Outputs ---
    assign priv_mode_id_o  = priv_lvl_q;
    assign priv_mode_lsu_o = priv_lvl_q;
    assign csr_mtvec_o     = mtvec_q;
    assign csr_mepc_o      = mepc_q;
    assign csr_rdata_o     = csr_read_data;
    // assign csr_mstatus_mie_o = mstatus_mie; // Omitted as per v0.1 scope

endmodule : qcv_cs_registers
