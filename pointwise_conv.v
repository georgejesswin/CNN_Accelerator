module pointwise_layer_stream #(
    parameter DATA_W   = 8,
    parameter ACC_W    = 64,
    parameter CIN      = 32,
    parameter COUT     = 64,
    parameter PAR_CIN       = 16,
    parameter PAR_COUT       = 16
)(
    input  wire clk,
    input  wire reset,

    // ===============================================
    // AXI-Stream Slave Input
    // ===============================================
    input  wire [CIN*DATA_W-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,

    // ===============================================
    // AXI-Stream Master Output
    // ===============================================
    output wire [COUT*DATA_W-1:0] m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,

    // ===============================================
    // Weight Load Interface
    // ===============================================
    input  wire                         pw_wr_en,
    input  wire [$clog2(COUT*CIN)-1:0]  pw_wr_addr,
    input  wire signed [DATA_W-1:0]     pw_wr_data,

    // ===============================================
    // Interrupt
    // ===============================================
    output wire o_intr
);

    // =========================================================
    // Parallelism Configuration
    // =========================================================

    localparam NUM_CIN_ITER  = (CIN  + PAR_CIN  - 1) / PAR_CIN;
    localparam NUM_COUT_ITER = (COUT + PAR_COUT - 1) / PAR_COUT;

    // Must match MAC datapath latency:
    // 2 + TREE_LVL  (TREE_LVL = log2(PAR_CIN))
    localparam MAC_LATENCY = 2 + $clog2(PAR_CIN);

    // =========================================================
    // Internal Signals
    // =========================================================
    wire                                  acc_clear;
    wire                                  acc_enable;
    wire signed [PAR_COUT*ACC_W-1:0]      acc_out;

    wire signed [CIN*DATA_W-1:0]          feature_full_reg;
    wire signed [PAR_CIN*DATA_W-1:0]      feature_slice;

    wire signed [PAR_COUT*PAR_CIN*DATA_W-1:0] weight_vec_block;

    wire [$clog2(NUM_CIN_ITER)-1:0]       cin_blk_idx;
    wire [$clog2(NUM_COUT_ITER)-1:0]      cout_blk_idx;

    wire signed [COUT*DATA_W-1:0]         fsm_out_vec;
    wire                                  fsm_m_axis_tvalid;

    // =========================================================
    // FSM Controller
    // =========================================================
    pointwise_conv1x1_fsm_axis #(
        .DATA_W       (DATA_W),
        .ACC_W        (ACC_W),
        .CIN          (CIN),
        .COUT         (COUT),
        .PAR_CIN      (PAR_CIN),
        .PAR_COUT     (PAR_COUT),
        .MAC_LATENCY  (MAC_LATENCY)
    ) FSM (
        .clk            (clk),
        .reset          (reset),

        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .m_axis_tvalid  (fsm_m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),

        .feature_vec    (s_axis_tdata),      // full CIN vector
        .acc_out        (acc_out),

        .acc_clear      (acc_clear),
        .acc_enable     (acc_enable),

        .out_vec        (fsm_out_vec),
        .feature_reg    (feature_full_reg),  // full latched CIN vector

        .cin_blk_idx    (cin_blk_idx),
        .cout_blk_idx   (cout_blk_idx),

        .o_intr         (o_intr)
    );

    // =========================================================
    // Feature Block Slicing
    // =========================================================
    assign feature_slice =
        feature_full_reg[
            cin_blk_idx * PAR_CIN * DATA_W +: PAR_CIN * DATA_W
        ];

    // =========================================================
    // Weight Register File (Tiled BRAM)
    // =========================================================
    pointwise_weight_regs #(
        .DATA_W   (DATA_W),
        .CIN      (CIN),
        .COUT     (COUT),
        .PAR_CIN  (PAR_CIN),
        .PAR_COUT (PAR_COUT)
    ) PW_WREGS (
        .clk          (clk),
        .reset        (reset),
        .wr_en        (pw_wr_en),
        .wr_addr      (pw_wr_addr),
        .wr_data      (pw_wr_data),
        .cin_blk_idx  (cin_blk_idx),
        .cout_blk_idx (cout_blk_idx),
        .weight_vec   (weight_vec_block)
    );

    // =========================================================
    // MAC Datapath (PAR_CIN × PAR_COUT Parallel Engine)
    // =========================================================
    pointwise_mac_datapath #(
        .DATA_W   (DATA_W),
        .ACC_W    (ACC_W),
        .PAR_CIN  (PAR_CIN),
        .PAR_COUT (PAR_COUT)
    ) MAC_DP (
        .clk         (clk),
        .reset       (reset),
        .acc_clear   (acc_clear),
        .acc_enable  (acc_enable),
        .feature_vec (feature_slice),   // sliced block
        .weight_vec  (weight_vec_block),
        .acc_out     (acc_out)
    );

    // =========================================================
    // AXI Output
    // =========================================================
    assign m_axis_tdata  = fsm_out_vec;
    assign m_axis_tvalid = fsm_m_axis_tvalid;

endmodule
