// Register File (Flip-Flop based)

module qcv_register_file_ff (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Read Port A (rs1)
    input  wire [4:0]  raddr_a_i,
    output wire [31:0] rdata_a_o,

    // Read Port B (rs2)
    input  wire [4:0]  raddr_b_i,
    output wire [31:0] rdata_b_o,

    // Write Port A (rd)
    input  wire [4:0]  waddr_a_i,
    input  wire [31:0] wdata_a_i,
    input  wire        we_a_i
);

    // Register array (x1-x31)
    reg [31:0] rf_reg_q [31:1];

    // Write Logic (Sequential)
    integer i;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Asynchronous reset: Clear all registers
            for (i = 1; i <= 31; i = i + 1) begin
                rf_reg_q[i] <= 32'b0;
            end
        end else begin
            // Synchronous write on positive clock edge
            if (we_a_i && (waddr_a_i != 5'b0)) begin
                rf_reg_q[waddr_a_i] <= wdata_a_i;
            end
        end
    end

    // Read Logic (Combinational)
    // Port A (rs1)
    assign rdata_a_o = (raddr_a_i == 5'b0) ? 32'b0 : rf_reg_q[raddr_a_i];

    // Port B (rs2)
    assign rdata_b_o = (raddr_b_i == 5'b0) ? 32'b0 : rf_reg_q[raddr_b_i];

endmodule : qcv_register_file_ff
