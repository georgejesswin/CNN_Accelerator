module depthwise_layer_stream #(
    parameter DATA_W    = 8,
    parameter IMG_WIDTH = 224,
    parameter CHANNELS  = 32
)(
    input  wire clk,
    input  wire reset,

    // ===============================
    // AXI-Stream Slave
    // ===============================
    input  wire [CHANNELS*DATA_W-1:0] s_axis_tdata,
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,

    // ===============================
    // AXI-Stream Master
    // ===============================
    output wire [CHANNELS*DATA_W-1:0] m_axis_tdata,
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,

    // ===============================
    // Kernel Load
    // ===============================
    input  wire                        kernel_wr_en,
    input  wire [$clog2(CHANNELS*9)-1:0] kernel_wr_addr,
    input  wire signed [DATA_W-1:0]    kernel_wr_data,

    // ===============================
    // Interrupt
    // ===============================
    output wire                        o_intr
);

    // =========================================================
    // Kernel Storage
    // =========================================================
    wire signed [CHANNELS*9*DATA_W-1:0] kernel_all;

    kernel_regs_multi #(
        .DATA_W(DATA_W),
        .CHANNELS(CHANNELS)
    ) KERNEL_FILE (
        .clk        (clk),
        .reset      (reset),
        .wr_en      (kernel_wr_en),
        .wr_addr    (kernel_wr_addr),
        .wr_data    (kernel_wr_data),
        .kernel_out (kernel_all)
    );

    // =========================================================
    // AXI Stall Logic (Correct Form)
    // =========================================================
    reg  [CHANNELS*DATA_W-1:0] m_axis_tdata_reg;
    reg                        m_axis_tvalid_reg;

    wire stall;
    assign stall = m_axis_tvalid_reg && !m_axis_tready;

    // Backpressure only at input boundary
    assign s_axis_tready = !stall;

    // Pipeline enable (input handshake)
    wire pipe_enable = s_axis_tvalid && s_axis_tready;

    // =========================================================
    // Per-channel processing
    // =========================================================
    wire [CHANNELS*9*DATA_W-1:0] win_all;
    wire [CHANNELS-1:0]          win_valid_vec;

    wire [CHANNELS*DATA_W-1:0]   conv_out_all;
    wire [CHANNELS-1:0]          conv_valid_vec;

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : DW_CHANNELS

            wire [DATA_W-1:0] pixel_ch;
            assign pixel_ch = s_axis_tdata[ch*DATA_W +: DATA_W];

            // 3x3 Window Generator
            image_control #(
                .DATA_W(DATA_W),
                .IMG_WIDTH(IMG_WIDTH)
            ) IMC (
                .clk            (clk),
                .reset          (reset),
                .in_pixel       (pixel_ch),
                .in_pixel_valid (pipe_enable),
                .out_pixel      (win_all[ch*9*DATA_W +: 9*DATA_W]),
                .out_valid      (win_valid_vec[ch])
            );

            // Depthwise Convolution
            depthwise_conv3x3 #(
                .DATA_W(DATA_W),
                .ACC_W (32)
            ) DW_CONV (
                .clk         (clk),
                .reset       (reset),
                .in_pixel    (win_all[ch*9*DATA_W +: 9*DATA_W]),
                .pixel_valid (win_valid_vec[ch]),   // ✅ NO stall gating
                .kernel      (kernel_all[ch*9*DATA_W +: 9*DATA_W]),
                .out_pixel   (conv_out_all[ch*DATA_W +: DATA_W]),
                .out_valid   (conv_valid_vec[ch])
            );

        end
    endgenerate

    // =========================================================
    // All channels are aligned → use one valid
    // =========================================================
    wire all_valid;
    assign all_valid = conv_valid_vec[0];  // all channels identical timing

    // =========================================================
    // AXI Output Register (Fully Correct)
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tdata_reg  <= {(CHANNELS*DATA_W){1'b0}};
        end
        else begin
            // If currently stalled → hold data
            if (stall) begin
                m_axis_tvalid_reg <= m_axis_tvalid_reg;
                m_axis_tdata_reg  <= m_axis_tdata_reg;
            end
            else begin
                m_axis_tvalid_reg <= all_valid;
                m_axis_tdata_reg  <= conv_out_all;
            end
        end
    end

    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;

    // =========================================================
    // Interrupt (rising edge of first valid)
    // =========================================================
    reg prev_valid;

    always @(posedge clk) begin
        if (reset)
            prev_valid <= 1'b0;
        else
            prev_valid <= m_axis_tvalid_reg;
    end

    assign o_intr = m_axis_tvalid_reg && !prev_valid;

endmodule
