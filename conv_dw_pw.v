// =============================================================
// Top-level DW + PW Neural Network Accelerator
// Direct AXI streaming connection (No FIFOs)
// =============================================================
module conv_dw_pw_top #(
    parameter DATA_W    = 8,
    parameter IMG_WIDTH = 224,
    parameter CIN       = 32,
    parameter COUT      = 64,
    parameter PAR_CIN       = 16,
    parameter PAR_COUT       = 16
)(
    input  wire                  clk,
    input  wire                  reset,   // ACTIVE HIGH

    // ===============================
    // AXI-Stream Slave Input
    // ===============================
    input  wire [CIN*DATA_W-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,

    // ===============================
    // AXI-Stream Master Output
    // ===============================
    output wire [COUT*DATA_W-1:0] m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,

    // ===============================
    // Depthwise Kernel Load
    // ===============================
    input  wire                         dw_kernel_wr_en,
    input  wire [$clog2(CIN*9)-1:0]      dw_kernel_wr_addr,
    input  wire signed [DATA_W-1:0]      dw_kernel_wr_data,

    // ===============================
    // Pointwise Weight Load
    // ===============================
    input  wire                         pw_wr_en,
    input  wire [$clog2(COUT*CIN)-1:0]   pw_wr_addr,
    input  wire signed [DATA_W-1:0]      pw_wr_data,

    // ===============================
    // Interrupts
    // ===============================
    output wire o_intr_dw,
    output wire o_intr_pw
);

    // =========================================================
    // Depthwise → Pointwise AXI signals
    // =========================================================
    wire [CIN*DATA_W-1:0] dw_to_pw_data;
    wire                  dw_to_pw_valid;
    wire                  dw_to_pw_ready;

    // =========================================================
    // DEPTHWISE LAYER
    // =========================================================
    depthwise_layer_stream #(
        .DATA_W(DATA_W),
        .IMG_WIDTH(IMG_WIDTH),
        .CHANNELS(CIN)
    ) DW_LAYER (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),

        .m_axis_tdata(dw_to_pw_data),
        .m_axis_tvalid(dw_to_pw_valid),
        .m_axis_tready(dw_to_pw_ready),

        .kernel_wr_en(dw_kernel_wr_en),
        .kernel_wr_addr(dw_kernel_wr_addr),
        .kernel_wr_data(dw_kernel_wr_data),

        .o_intr(o_intr_dw)
    );

    // =========================================================
    // POINTWISE LAYER (Directly Connected)
    // =========================================================
    pointwise_layer_stream #(
        .DATA_W(DATA_W),
        .ACC_W(64),
        .CIN(CIN),
        .COUT(COUT),
        .PAR_CIN(PAR_CIN),
        .PAR_COUT(PAR_COUT)
    ) PW_LAYER (
        .clk(clk),
        .reset(reset),

        .s_axis_tdata(dw_to_pw_data),
        .s_axis_tvalid(dw_to_pw_valid),
        .s_axis_tready(dw_to_pw_ready),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),

        .pw_wr_en(pw_wr_en),
        .pw_wr_addr(pw_wr_addr),
        .pw_wr_data(pw_wr_data),

        .o_intr(o_intr_pw)
    );

endmodule
