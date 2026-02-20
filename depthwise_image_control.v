module image_control #(
    parameter DATA_W    = 8,
    parameter IMG_WIDTH = 512
)(
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     in_pixel_valid,
    input  wire [DATA_W-1:0]        in_pixel,

    output reg  [9*DATA_W-1:0]      out_pixel,
    output reg                      out_valid
);

    localparam COL_W = $clog2(IMG_WIDTH);

    // ----------------------------------------------------------
    // Counters
    // ----------------------------------------------------------
    reg [COL_W-1:0] col_cnt;
    reg [15:0]      row_cnt;

    always @(posedge clk) begin
        if (reset) begin
            col_cnt <= 0;
            row_cnt <= 0;
        end
        else if (in_pixel_valid) begin
            if (col_cnt == IMG_WIDTH-1) begin
                col_cnt <= 0;
                row_cnt <= row_cnt + 1;
            end
            else begin
                col_cnt <= col_cnt + 1;
            end
        end
    end

    // ----------------------------------------------------------
    // Stage 0 → Delay input
    // ----------------------------------------------------------
    reg [DATA_W-1:0] in_pixel_d;
    reg [COL_W-1:0]  col_cnt_d;
    reg [15:0]       row_cnt_d;
    reg              valid_d;

    always @(posedge clk) begin
        if (reset) begin
            in_pixel_d <= 0;
            col_cnt_d  <= 0;
            row_cnt_d  <= 0;
            valid_d    <= 0;
        end
        else begin
            in_pixel_d <= in_pixel;
            col_cnt_d  <= col_cnt;
            row_cnt_d  <= row_cnt;
            valid_d    <= in_pixel_valid;
        end
    end

    // ----------------------------------------------------------
    // Line buffers (true BRAM safe)
    // ----------------------------------------------------------
    (* ram_style = "block" *)
    reg [DATA_W-1:0] linebuf0 [0:IMG_WIDTH-1];

    (* ram_style = "block" *)
    reg [DATA_W-1:0] linebuf1 [0:IMG_WIDTH-1];

    reg [DATA_W-1:0] lb0_data;
    reg [DATA_W-1:0] lb1_data;

    // Stage 1 → READ ONLY
    always @(posedge clk) begin
        if (valid_d) begin
            lb0_data <= linebuf0[col_cnt_d];
            lb1_data <= linebuf1[col_cnt_d];
        end
    end

    // Stage 2 → WRITE ONLY
    always @(posedge clk) begin
        if (valid_d) begin
            linebuf0[col_cnt_d] <= in_pixel_d;
            linebuf1[col_cnt_d] <= lb0_data;
        end
    end

    // ----------------------------------------------------------
    // Shift registers
    // ----------------------------------------------------------
    reg [DATA_W-1:0] r0_s0, r0_s1, r0_s2;
    reg [DATA_W-1:0] r1_s0, r1_s1, r1_s2;
    reg [DATA_W-1:0] r2_s0, r2_s1, r2_s2;

    always @(posedge clk) begin
        if (reset) begin
            r0_s0<=0; r0_s1<=0; r0_s2<=0;
            r1_s0<=0; r1_s1<=0; r1_s2<=0;
            r2_s0<=0; r2_s1<=0; r2_s2<=0;
        end
        else if (valid_d) begin
            r0_s2 <= r0_s1;
            r0_s1 <= r0_s0;
            r0_s0 <= lb1_data;

            r1_s2 <= r1_s1;
            r1_s1 <= r1_s0;
            r1_s0 <= lb0_data;

            r2_s2 <= r2_s1;
            r2_s1 <= r2_s0;
            r2_s0 <= in_pixel_d;
        end
    end

    // ----------------------------------------------------------
    // Output window
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            out_pixel <= 0;
            out_valid <= 0;
        end
        else if (valid_d) begin
            if (row_cnt_d >= 2 && col_cnt_d >= 2) begin
                out_pixel <= {
                    r0_s2, r0_s1, r0_s0,
                    r1_s2, r1_s1, r1_s0,
                    r2_s2, r2_s1, r2_s0
                };
                out_valid <= 1'b1;
            end
            else begin
                out_valid <= 1'b0;
            end
        end
        else begin
            out_valid <= 1'b0;
        end
    end

endmodule
