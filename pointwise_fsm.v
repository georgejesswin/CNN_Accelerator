module pointwise_conv1x1_fsm_axis #(
    parameter DATA_W   = 8,
    parameter ACC_W    = 64,
    parameter CIN      = 32,
    parameter COUT     = 64,
    parameter PAR_CIN  = 8,
    parameter PAR_COUT = 8,
    parameter MAC_LATENCY = 5
)(
    input  wire clk,
    input  wire reset,

    // AXI
    input  wire s_axis_tvalid,
    output wire s_axis_tready,
    output wire m_axis_tvalid,
    input  wire m_axis_tready,

    // Datapath
    input  wire signed [PAR_CIN*DATA_W-1:0] feature_vec,
    input  wire signed [PAR_COUT*ACC_W-1:0] acc_out,

    output reg  acc_clear,
    output reg  acc_enable,

    output reg signed [COUT*DATA_W-1:0] out_vec,
    output reg signed [PAR_CIN*DATA_W-1:0] feature_reg,

    output reg [$clog2((CIN+PAR_CIN-1)/PAR_CIN)-1:0]   cin_blk_idx,
    output reg [$clog2((COUT+PAR_COUT-1)/PAR_COUT)-1:0] cout_blk_idx,

    output reg o_intr
);

    // =========================================================
    // Derived Parameters
    // =========================================================
    localparam NUM_CIN_ITER  = (CIN  + PAR_CIN  - 1) / PAR_CIN;
    localparam NUM_COUT_ITER = (COUT + PAR_COUT - 1) / PAR_COUT;

    localparam IDLE      = 3'd0,
               LOAD      = 3'd1,
               ACCUM     = 3'd2,
               WAIT_PIPE = 3'd3,
               STORE     = 3'd4,
               DONE      = 3'd5;

    reg [2:0] state, next_state;

    reg [$clog2(NUM_CIN_ITER)-1:0]  cin_cnt;
    reg [$clog2(NUM_COUT_ITER)-1:0] cout_cnt;
    reg [$clog2(MAC_LATENCY)-1:0]   pipe_cnt;

    // =========================================================
    // State Register
    // =========================================================
    always @(posedge clk)
        if (reset)
            state <= IDLE;
        else
            state <= next_state;

    // =========================================================
    // Next-State Logic
    // =========================================================
    always @(*) begin
        next_state = state;

        case (state)

            IDLE:
                if (s_axis_tvalid)
                    next_state = LOAD;

            LOAD:
                next_state = ACCUM;

            ACCUM:
                if (cin_cnt == NUM_CIN_ITER-1)
                    next_state = WAIT_PIPE;

            WAIT_PIPE:
                if (pipe_cnt == MAC_LATENCY-1)
                    next_state = STORE;

            STORE:
                if (cout_cnt == NUM_COUT_ITER-1)
                    next_state = DONE;
                else
                    next_state = LOAD;

            DONE:
                if (m_axis_tready)
                    next_state = IDLE;

        endcase
    end

    // =========================================================
    // Saturation
    // =========================================================
    function automatic signed [DATA_W-1:0] saturate;
        input signed [ACC_W-1:0] val;
        begin
            if (val > 127)
                saturate = 127;
            else if (val < -128)
                saturate = -128;
            else
                saturate = val[DATA_W-1:0];
        end
    endfunction

    // =========================================================
    // Sequential Control Logic
    // =========================================================
    integer g;

    always @(posedge clk) begin
        if (reset) begin
            cin_cnt      <= 0;
            cout_cnt     <= 0;
            pipe_cnt     <= 0;
            cin_blk_idx  <= 0;
            cout_blk_idx <= 0;
            acc_enable   <= 0;
            acc_clear    <= 0;
            out_vec      <= 0;
            feature_reg  <= 0;
            o_intr       <= 0;
        end
        else begin
            // default signals
            acc_enable <= 0;
            acc_clear  <= 0;
            o_intr     <= 0;

            // =================================================
            // Correct pipe counter handling
            // =================================================
            if (state == ACCUM && next_state == WAIT_PIPE)
                pipe_cnt <= 0;
            else if (state == WAIT_PIPE)
                pipe_cnt <= pipe_cnt + 1;

            case (state)

                //------------------------------------------------
                IDLE:
                //------------------------------------------------
                begin
                    cin_cnt  <= 0;
                    cout_cnt <= 0;
                end

                //------------------------------------------------
                LOAD:
                //------------------------------------------------
                begin
                    feature_reg  <= feature_vec;  // latch input
                    cin_cnt      <= 0;
                    cin_blk_idx  <= 0;
                    cout_blk_idx <= cout_cnt;
                    acc_clear    <= 1;
                end

                //------------------------------------------------
                ACCUM:
                //------------------------------------------------
                begin
                    acc_enable  <= 1;
                    cin_blk_idx <= cin_cnt;

                    if (cin_cnt != NUM_CIN_ITER-1)
                        cin_cnt <= cin_cnt + 1;
                end

                //------------------------------------------------
                WAIT_PIPE:
                //------------------------------------------------
                begin
                    // pipeline draining handled above
                end

                //------------------------------------------------
                STORE:
                //------------------------------------------------
                begin
                    for (g = 0; g < PAR_COUT; g = g + 1)
                        if ((cout_cnt*PAR_COUT + g) < COUT)
                            out_vec[(cout_cnt*PAR_COUT + g)*DATA_W +: DATA_W]
                                <= saturate(acc_out[g*ACC_W +: ACC_W]);

                    if (cout_cnt != NUM_COUT_ITER-1)
                        cout_cnt <= cout_cnt + 1;
                end

                //------------------------------------------------
                DONE:
                //------------------------------------------------
                begin
                    o_intr <= 1;
                end

            endcase
        end
    end

    // =========================================================
    // AXI Handshake
    // =========================================================
    assign s_axis_tready = (state == IDLE);
    assign m_axis_tvalid = (state == DONE);

endmodule
