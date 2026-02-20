module depthwise_conv3x3 #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                         clk,
    input  wire                         reset,
    input  wire signed [9*DATA_W-1:0]   in_pixel,
    input  wire                         pixel_valid,
    input  wire signed [9*DATA_W-1:0]   kernel,

    output reg  signed [DATA_W-1:0]     out_pixel,
    output wire                         out_valid
);

    // =========================================================
    // Stage 0: 9 Parallel Multipliers (DSP inferred)
    // =========================================================
    (* use_dsp = "yes" *)
    reg signed [2*DATA_W-1:0] mult [0:8];

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 9; i = i + 1)
                mult[i] <= 0;
        end 
        else if (pixel_valid) begin
            for (i = 0; i < 9; i = i + 1) begin
                mult[i] <=
                    $signed(in_pixel[DATA_W*i +: DATA_W]) *
                    $signed(kernel  [DATA_W*i +: DATA_W]);
            end
        end
    end

    // =========================================================
    // Valid Pipeline (6-cycle total latency)
    // =========================================================
    reg vld1, vld2, vld3, vld4, vld5, vld6;

    always @(posedge clk) begin
        if (reset) begin
            vld1 <= 0; vld2 <= 0; vld3 <= 0;
            vld4 <= 0; vld5 <= 0; vld6 <= 0;
        end else begin
            vld1 <= pixel_valid;
            vld2 <= vld1;
            vld3 <= vld2;
            vld4 <= vld3;
            vld5 <= vld4;
            vld6 <= vld5;
        end
    end

    // =========================================================
    // Helper: Sign-extend multiplier to ACC_W
    // =========================================================
    function signed [ACC_W-1:0] sx;
        input signed [2*DATA_W-1:0] val;
        begin
            sx = {{(ACC_W-2*DATA_W){val[2*DATA_W-1]}}, val};
        end
    endfunction

    // =========================================================
    // Stage 1: Adder Tree Level 1
    // =========================================================
    reg signed [ACC_W-1:0] add_l1 [0:3];

    always @(posedge clk) begin
        if (reset) begin
            add_l1[0] <= 0; add_l1[1] <= 0;
            add_l1[2] <= 0; add_l1[3] <= 0;
        end
        else if (vld1) begin
            add_l1[0] <= sx(mult[0]) + sx(mult[1]);
            add_l1[1] <= sx(mult[2]) + sx(mult[3]);
            add_l1[2] <= sx(mult[4]) + sx(mult[5]);
            add_l1[3] <= sx(mult[6]) + sx(mult[7]);
        end
    end

    // =========================================================
    // Stage 2: Adder Tree Level 2
    // =========================================================
    reg signed [ACC_W-1:0] add_l2 [0:1];

    always @(posedge clk) begin
        if (reset) begin
            add_l2[0] <= 0;
            add_l2[1] <= 0;
        end
        else if (vld2) begin
            add_l2[0] <= add_l1[0] + add_l1[1];
            add_l2[1] <= add_l1[2] + add_l1[3];
        end
    end

    // =========================================================
    // Align mult[8] (always shift for bubble safety)
    // =========================================================
    reg signed [2*DATA_W-1:0] mult8_d1, mult8_d2;

    always @(posedge clk) begin
        if (reset) begin
            mult8_d1 <= 0;
            mult8_d2 <= 0;
        end
        else begin
            mult8_d1 <= mult[8];
            mult8_d2 <= mult8_d1;
        end
    end

    // =========================================================
    // Stage 3: Final Reduction
    // =========================================================
    reg signed [ACC_W-1:0] add_l3;

    always @(posedge clk) begin
        if (reset)
            add_l3 <= 0;
        else if (vld3)
            add_l3 <= add_l2[0] + add_l2[1];
    end

    // =========================================================
    // Stage 4: Final Accumulation
    // =========================================================
    reg signed [ACC_W-1:0] sum_reg;

    always @(posedge clk) begin
        if (reset)
            sum_reg <= 0;
        else if (vld4)
            sum_reg <= add_l3 + sx(mult8_d2);
    end

    // =========================================================
    // Stage 5: INT8 Saturation
    // =========================================================
    localparam signed [ACC_W-1:0] MAX_VAL =  127;
    localparam signed [ACC_W-1:0] MIN_VAL = -128;

    always @(posedge clk) begin
        if (reset)
            out_pixel <= 0;
        else if (vld5) begin
            if (sum_reg > MAX_VAL)
                out_pixel <= 127;
            else if (sum_reg < MIN_VAL)
                out_pixel <= -128;
            else
                out_pixel <= sum_reg[DATA_W-1:0];
        end
    end

    assign out_valid = vld6;

endmodule
