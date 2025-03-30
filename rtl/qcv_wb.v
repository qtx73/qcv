// Write Back Stage (Combinational)

module qcv_wb (
    input  wire        clk_i,              // Unused in v0.1 logic
    input  wire        rst_ni,             // Unused in v0.1 logic

    // Inputs from ID Stage
    input  wire        en_wb_i,            // Instruction complete signal
    input  wire [4:0]  rf_waddr_id_i,      // Write address from ID
    input  wire [31:0] rf_wdata_id_i,      // Write data from ID (ALU/CSR result)
    input  wire        rf_we_id_i,         // Write enable from ID

    // Inputs from LSU
    input  wire [31:0] rf_wdata_lsu_i,     // Write data from LSU (Load data)
    input  wire        rf_we_lsu_i,        // Write enable from LSU
    input  wire        lsu_resp_valid_i,   // LSU response valid (unused in v0.1 logic)
    input  wire        lsu_resp_err_i,     // LSU error (unused in v0.1 logic)

    // Outputs to Register File
    output wire [4:0]  rf_waddr_wb_o,      // Write address to RF
    output wire [31:0] rf_wdata_wb_o,      // Write data to RF
    output wire        rf_we_wb_o          // Write enable to RF
);

    // --- Combinational Logic ---

    // Write Address Pass-through
    assign rf_waddr_wb_o = rf_waddr_id_i;

    // Write Data Mux
    // Select based on which source provides the write enable.
    // Assumes rf_we_id_i and rf_we_lsu_i are mutually exclusive.
    assign rf_wdata_wb_o = rf_we_lsu_i ? rf_wdata_lsu_i : rf_wdata_id_i;

    // Write Enable Generation
    // Enable write if either ID stage (ALU/CSR result) or LSU (Load result) requests it.
    assign rf_we_wb_o = rf_we_id_i | rf_we_lsu_i;

    // Note: en_wb_i is an input indicating instruction completion in ID/EX/LSU,
    // but it's not directly used in this combinational logic for data selection.
    // The individual write enables (rf_we_id_i, rf_we_lsu_i) already factor in
    // the instruction completion and validity from previous stages.

endmodule : qcv_wb
