module pointwise_weight_regs #(
    parameter DATA_W   = 8,
    parameter CIN      = 32,
    parameter COUT     = 64,
    parameter PAR_CIN  = 8,
    parameter PAR_COUT = 8
)(
    input  wire clk,
    input  wire reset,

    // Linear weight write interface
    input  wire                         wr_en,
    input  wire [$clog2(COUT*CIN)-1:0]  wr_addr,
    input  wire signed [DATA_W-1:0]     wr_data,

    // Block select from FSM
    input  wire [$clog2((COUT+PAR_COUT-1)/PAR_COUT)-1:0] cout_blk_idx,
    input  wire [$clog2((CIN +PAR_CIN -1)/PAR_CIN )-1:0] cin_blk_idx,

    // Block output to MAC
    output reg  signed [PAR_COUT*PAR_CIN*DATA_W-1:0] weight_vec
);

    // =========================================================
    // Parameters
    // =========================================================
    localparam NUM_CIN_BLKS  = (CIN  + PAR_CIN  - 1) / PAR_CIN;
    localparam NUM_COUT_BLKS = (COUT + PAR_COUT - 1) / PAR_COUT;
    localparam BLOCK_W       = PAR_COUT * PAR_CIN * DATA_W;
    localparam TOTAL_BLOCKS  = NUM_CIN_BLKS * NUM_COUT_BLKS;
    localparam TOTAL_WEIGHTS = COUT * CIN;

    // =========================================================
    // Tiled Weight Memory (True BRAM)
    // =========================================================
    (* ram_style = "block" *)
    reg signed [BLOCK_W-1:0] weight_mem [0:TOTAL_BLOCKS-1];

    // =========================================================
    // Decode Linear Address → Block Address
    // =========================================================
    wire [$clog2(COUT)-1:0] wr_cout;
    wire [$clog2(CIN)-1:0]  wr_cin;

    assign wr_cout = wr_addr / CIN;
    assign wr_cin  = wr_addr % CIN;

    wire [$clog2(NUM_COUT_BLKS)-1:0] wr_cout_blk;
    wire [$clog2(NUM_CIN_BLKS)-1:0]  wr_cin_blk;

    assign wr_cout_blk = wr_cout / PAR_COUT;
    assign wr_cin_blk  = wr_cin  / PAR_CIN;

    wire [$clog2(TOTAL_BLOCKS)-1:0] blk_idx;
    assign blk_idx = wr_cout_blk * NUM_CIN_BLKS + wr_cin_blk;

    wire [$clog2(PAR_COUT)-1:0] off_cout;
    wire [$clog2(PAR_CIN)-1:0]  off_cin;

    assign off_cout = wr_cout % PAR_COUT;
    assign off_cin  = wr_cin  % PAR_CIN;

    wire [$clog2(PAR_COUT*PAR_CIN)-1:0] elem_idx;
    assign elem_idx = off_cout * PAR_CIN + off_cin;

    wire [$clog2(BLOCK_W)-1:0] bit_idx;
    assign bit_idx = elem_idx * DATA_W;

    // =========================================================
    // Write (No Full BRAM Reset)
    // =========================================================
    always @(posedge clk) begin
        if (wr_en && (wr_addr < TOTAL_WEIGHTS)) begin
            weight_mem[blk_idx][bit_idx +: DATA_W] <= wr_data;
        end
    end

    // =========================================================
    // Read (1 Block Per Cycle)
    // =========================================================
    always @(posedge clk) begin
        weight_vec <=
            weight_mem[cout_blk_idx * NUM_CIN_BLKS + cin_blk_idx];
    end

endmodule
