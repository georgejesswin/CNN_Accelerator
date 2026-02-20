module kernel_regs_multi #(
    parameter DATA_W   = 8,
    parameter CHANNELS = 32
)(
    input  wire clk,
    input  wire reset,

    input  wire                         wr_en,
    input  wire [$clog2(CHANNELS*9)-1:0] wr_addr,
    input  wire signed [DATA_W-1:0]     wr_data,

    output wire signed [CHANNELS*9*DATA_W-1:0] kernel_out
);

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam TOTAL_WEIGHTS = CHANNELS * 9;

    // ------------------------------------------------------------
    // Kernel register storage (register-based, NOT BRAM)
    // ------------------------------------------------------------
    reg signed [DATA_W-1:0] kernel [0:TOTAL_WEIGHTS-1];

    integer i;

    // ------------------------------------------------------------
    // Reset + Write Logic
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < TOTAL_WEIGHTS; i = i + 1)
                kernel[i] <= {DATA_W{1'b0}};
        end
        else if (wr_en) begin
            kernel[wr_addr] <= wr_data;
        end
    end

    // ------------------------------------------------------------
    // Parallel Read (Combinational wiring)
    // ------------------------------------------------------------
    genvar j;
    generate
        for (j = 0; j < TOTAL_WEIGHTS; j = j + 1) begin : KERNEL_OUT_GEN
            assign kernel_out[j*DATA_W +: DATA_W] = kernel[j];
        end
    endgenerate

endmodule
