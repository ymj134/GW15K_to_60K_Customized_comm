module top
(
    input  wire clk,     // 50 MHz
    input  wire rst_n,
    output wire led,
    output wire sfp_tx_disable1     //60k板子需要逻辑控制这个信号
);

assign sfp_tx_disable1 = 1'b0 ;

localparam [31:0] TOP_VERSION = 32'h8B10_0002;
localparam [7:0]  K28_5_CODE  = 8'hBC;
localparam integer PRBS_WIDTH = 64;

// 上电后先连续发 K28.5，帮助 RX Word Alignment 建立
localparam integer TRAIN_K_WORDS      = 1024;

// 训练完成后，每隔 K_INSERT_INTERVAL 个 word 插入 1 个 K28.5 word
// 实际效果：1 个 K word + 1023 个 PRBS data word
localparam integer K_INSERT_INTERVAL  = 1024;

// -----------------------------------------------------------------------------
// Customized PHY Q0 Lane0 interface wires
// -----------------------------------------------------------------------------
wire        cphy_rx_pcs_clk;
wire [87:0] cphy_rx_data;
wire [4:0]  cphy_rx_fifo_rdusewd;
wire        cphy_rx_fifo_aempty;
wire        cphy_rx_fifo_empty;
wire        cphy_rx_valid;

wire        cphy_tx_pcs_clk;
wire [4:0]  cphy_tx_fifo_wrusewd;
wire        cphy_tx_fifo_afull;
wire        cphy_tx_fifo_full;

wire        cphy_refclk;
wire        cphy_signal_detect;
wire        cphy_rx_cdr_lock;
wire        cphy_pll_lock;
wire        cphy_k_lock;
wire        cphy_word_align_link;
wire        cphy_ready;

wire        cphy_rx_clk_i;
wire        cphy_rx_fifo_rden_i;
wire        cphy_tx_clk_i;
wire [79:0] cphy_tx_data_i;
wire        cphy_tx_fifo_wren_i;
wire        cphy_pma_rstn_i;
wire        cphy_pcs_rx_rst_i;
wire        cphy_pcs_tx_rst_i;

assign cphy_rx_clk_i = cphy_rx_pcs_clk;
assign cphy_tx_clk_i = cphy_tx_pcs_clk;

assign cphy_pma_rstn_i    = rst_n;
assign cphy_pcs_rx_rst_i  = ~rst_n;
assign cphy_pcs_tx_rst_i  = ~rst_n;

// RX FIFO read request.
// rden 只要求 PHY 基础状态正常，真正数据是否使用由 rx_valid + 8B10B 解包结果决定。
assign cphy_rx_fifo_rden_i = rst_n
                            & cphy_ready
                            & cphy_signal_detect
                            & cphy_rx_cdr_lock
                            & ~cphy_rx_fifo_aempty;

// -----------------------------------------------------------------------------
// Instantiate generated SerDes Customized PHY
// IP setting:
//   Line Rate              = 6.25G
//   TX/RX Internal Width   = 20
//   TX/RX External Ratio   = 1:4
//   TX/RX Encoding         = 8B10B
//   RX Word Alignment      = Enable, K28.5
//   RX Bit Polarity Invert = Enable
// -----------------------------------------------------------------------------
SerDes_Top u_SerDes_Top
(
    .Customized_PHY_Top_q0_ln3_rx_pcs_clkout_o   (cphy_rx_pcs_clk),
    .Customized_PHY_Top_q0_ln3_rx_data_o         (cphy_rx_data),
    .Customized_PHY_Top_q0_ln3_rx_fifo_rdusewd_o (cphy_rx_fifo_rdusewd),
    .Customized_PHY_Top_q0_ln3_rx_fifo_aempty_o  (cphy_rx_fifo_aempty),
    .Customized_PHY_Top_q0_ln3_rx_fifo_empty_o   (cphy_rx_fifo_empty),
    .Customized_PHY_Top_q0_ln3_rx_valid_o        (cphy_rx_valid),

    .Customized_PHY_Top_q0_ln3_tx_pcs_clkout_o   (cphy_tx_pcs_clk),
    .Customized_PHY_Top_q0_ln3_tx_fifo_wrusewd_o (cphy_tx_fifo_wrusewd),
    .Customized_PHY_Top_q0_ln3_tx_fifo_afull_o   (cphy_tx_fifo_afull),
    .Customized_PHY_Top_q0_ln3_tx_fifo_full_o    (cphy_tx_fifo_full),

    .Customized_PHY_Top_q0_ln3_refclk_o          (cphy_refclk),
    .Customized_PHY_Top_q0_ln3_signal_detect_o   (cphy_signal_detect),
    .Customized_PHY_Top_q0_ln3_rx_cdr_lock_o     (cphy_rx_cdr_lock),
    .Customized_PHY_Top_q0_ln3_pll_lock_o        (cphy_pll_lock),
    .Customized_PHY_Top_q0_ln3_k_lock_o          (cphy_k_lock),
    .Customized_PHY_Top_q0_ln3_word_align_link_o (cphy_word_align_link),
    .Customized_PHY_Top_q0_ln3_ready_o           (cphy_ready),

    .Customized_PHY_Top_q0_ln3_rx_clk_i          (cphy_rx_clk_i),
    .Customized_PHY_Top_q0_ln3_rx_fifo_rden_i    (cphy_rx_fifo_rden_i),
    .Customized_PHY_Top_q0_ln3_tx_clk_i          (cphy_tx_clk_i),
    .Customized_PHY_Top_q0_ln3_tx_data_i         (cphy_tx_data_i),
    .Customized_PHY_Top_q0_ln3_tx_fifo_wren_i    (cphy_tx_fifo_wren_i),
    .Customized_PHY_Top_q0_ln3_pma_rstn_i        (cphy_pma_rstn_i),
    .Customized_PHY_Top_q0_ln3_pcs_rx_rst_i      (cphy_pcs_rx_rst_i),
    .Customized_PHY_Top_q0_ln3_pcs_tx_rst_i      (cphy_pcs_tx_rst_i)
);

// -----------------------------------------------------------------------------
// TX/RX domain reset stretching
// -----------------------------------------------------------------------------
reg [7:0] tx_rstn_sr;
reg [7:0] rx_rstn_sr;

always @(posedge cphy_tx_pcs_clk or negedge rst_n) begin
    if (!rst_n)
        tx_rstn_sr <= 8'h00;
    else if (cphy_pll_lock && cphy_ready)
        tx_rstn_sr <= {tx_rstn_sr[6:0], 1'b1};
    else
        tx_rstn_sr <= 8'h00;
end

always @(posedge cphy_rx_pcs_clk or negedge rst_n) begin
    if (!rst_n)
        rx_rstn_sr <= 8'h00;
    else if (cphy_ready &&
             cphy_signal_detect &&
             cphy_rx_cdr_lock &&
             cphy_k_lock &&
             cphy_word_align_link)
        rx_rstn_sr <= {rx_rstn_sr[6:0], 1'b1};
    else
        rx_rstn_sr <= 8'h00;
end

wire tx_link_rstn = tx_rstn_sr[7];
wire rx_link_rstn = rx_rstn_sr[7];

// -----------------------------------------------------------------------------
// TX pattern scheduler
//   1. 上电后先发 TRAIN_K_WORDS 个 K28.5 word
//   2. 训练结束后周期性插入 K28.5
//   3. 其他周期发送 PRBS data word
// -----------------------------------------------------------------------------
reg [15:0] tx_train_cnt;
reg [15:0] tx_interval_cnt;

wire tx_in_training;
wire tx_periodic_k_word;
wire tx_send_k_word;
wire tx_send_data_word;

assign tx_in_training    = (tx_train_cnt < TRAIN_K_WORDS);
assign tx_periodic_k_word = (tx_interval_cnt == 16'd0);
assign tx_send_k_word    = tx_in_training | tx_periodic_k_word;
assign tx_send_data_word = ~tx_send_k_word;

assign cphy_tx_fifo_wren_i = tx_link_rstn & ~cphy_tx_fifo_afull;

always @(posedge cphy_tx_pcs_clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_train_cnt    <= 16'd0;
        tx_interval_cnt <= 16'd0;
    end else if (!tx_link_rstn) begin
        tx_train_cnt    <= 16'd0;
        tx_interval_cnt <= 16'd0;
    end else if (cphy_tx_fifo_wren_i) begin
        if (tx_train_cnt < TRAIN_K_WORDS) begin
            tx_train_cnt    <= tx_train_cnt + 16'd1;
            tx_interval_cnt <= 16'd0;
        end else begin
            if (tx_interval_cnt == K_INSERT_INTERVAL - 1)
                tx_interval_cnt <= 16'd0;
            else
                tx_interval_cnt <= tx_interval_cnt + 16'd1;
        end
    end
end

// -----------------------------------------------------------------------------
// PRBS7 generator/checker
//   TX PRBS 只在发送 data word 时前进
//   RX PRBS 只在收到普通 D data word 时前进
// -----------------------------------------------------------------------------
wire [PRBS_WIDTH-1:0] prbs_tx_data;
wire [PRBS_WIDTH-1:0] prbs_rx_data;
wire                  prbs_lock;

wire tx_prbs_en;
wire rx_prbs_en;

assign tx_prbs_en = cphy_tx_fifo_wren_i & tx_send_data_word;

// -----------------------------------------------------------------------------
// 8B10B TX pack
//
// TX slot format when 8B10B enabled:
//   [7:0]    = Code0, [8]  = K0, [9]  = N/A
//   [17:10]  = Code1, [18] = K1, [19] = N/A
//   ...
//   [77:70]  = Code7, [78] = K7, [79] = N/A
// -----------------------------------------------------------------------------
wire [63:0] tx_code;
wire [7:0]  tx_k;

assign tx_code = tx_send_k_word ? {8{K28_5_CODE}} : prbs_tx_data;
assign tx_k    = tx_send_k_word ? 8'hFF          : 8'h00;

assign cphy_tx_data_i = {
    1'b0, tx_k[7], tx_code[63:56],  // [79]=N/A, [78]=K7, [77:70]=Code7
    1'b0, tx_k[6], tx_code[55:48],  // [69]=N/A, [68]=K6, [67:60]=Code6
    1'b0, tx_k[5], tx_code[47:40],  // [59]=N/A, [58]=K5, [57:50]=Code5
    1'b0, tx_k[4], tx_code[39:32],  // [49]=N/A, [48]=K4, [47:40]=Code4
    1'b0, tx_k[3], tx_code[31:24],  // [39]=N/A, [38]=K3, [37:30]=Code3
    1'b0, tx_k[2], tx_code[23:16],  // [29]=N/A, [28]=K2, [27:20]=Code2
    1'b0, tx_k[1], tx_code[15:8],   // [19]=N/A, [18]=K1, [17:10]=Code1
    1'b0, tx_k[0], tx_code[7:0]     // [9] =N/A, [8] =K0, [7:0]  =Code0
};

// -----------------------------------------------------------------------------
// 8B10B RX unpack
//
// RX slot format when 8B10B enabled:
//   [7:0]    = Code0, [8]  = K0, [9]  = Disparity Error0, [80] = Decoder Error0
//   [17:10]  = Code1, [18] = K1, [19] = Disparity Error1, [81] = Decoder Error1
//   ...
//   [77:70]  = Code7, [78] = K7, [79] = Disparity Error7, [87] = Decoder Error7
// -----------------------------------------------------------------------------
wire [63:0] rx_code;
wire [7:0]  rx_k;
wire [7:0]  rx_disp_err;
wire [7:0]  rx_dec_err;

assign rx_code = {
    cphy_rx_data[77:70],  // Code7
    cphy_rx_data[67:60],  // Code6
    cphy_rx_data[57:50],  // Code5
    cphy_rx_data[47:40],  // Code4
    cphy_rx_data[37:30],  // Code3
    cphy_rx_data[27:20],  // Code2
    cphy_rx_data[17:10],  // Code1
    cphy_rx_data[7:0]     // Code0
};

assign rx_k = {
    cphy_rx_data[78],     // K7
    cphy_rx_data[68],     // K6
    cphy_rx_data[58],     // K5
    cphy_rx_data[48],     // K4
    cphy_rx_data[38],     // K3
    cphy_rx_data[28],     // K2
    cphy_rx_data[18],     // K1
    cphy_rx_data[8]       // K0
};

assign rx_disp_err = {
    cphy_rx_data[79],     // Disparity Error7
    cphy_rx_data[69],     // Disparity Error6
    cphy_rx_data[59],     // Disparity Error5
    cphy_rx_data[49],     // Disparity Error4
    cphy_rx_data[39],     // Disparity Error3
    cphy_rx_data[29],     // Disparity Error2
    cphy_rx_data[19],     // Disparity Error1
    cphy_rx_data[9]       // Disparity Error0
};

assign rx_dec_err = {
    cphy_rx_data[87],     // Decoder Error7
    cphy_rx_data[86],     // Decoder Error6
    cphy_rx_data[85],     // Decoder Error5
    cphy_rx_data[84],     // Decoder Error4
    cphy_rx_data[83],     // Decoder Error3
    cphy_rx_data[82],     // Decoder Error2
    cphy_rx_data[81],     // Decoder Error1
    cphy_rx_data[80]      // Decoder Error0
};

wire rx_8b10b_no_err;
wire rx_all_k285;
wire rx_is_data_word;
wire rx_is_valid_k_word;
wire rx_unexpected_word;

assign rx_8b10b_no_err = (rx_disp_err == 8'h00) && (rx_dec_err == 8'h00);
assign rx_all_k285     = (rx_code == {8{K28_5_CODE}}) && (rx_k == 8'hFF);

assign rx_is_valid_k_word = cphy_rx_valid & rx_8b10b_no_err & rx_all_k285;
assign rx_is_data_word    = cphy_rx_valid & rx_8b10b_no_err & (rx_k == 8'h00);

assign rx_unexpected_word = cphy_rx_valid
                          & (
                                !rx_8b10b_no_err
                             || ((rx_k != 8'h00) && !rx_all_k285)
                            );

assign prbs_rx_data = rx_code;
assign rx_prbs_en   = rx_link_rstn & rx_is_data_word;

prbs7_single_channel #(
    .WIDTH(PRBS_WIDTH)
) u_prbs7_single_channel (
    // TX PRBS generator
    .tx_clk_i  (cphy_tx_pcs_clk),
    .tx_rstn_i (tx_link_rstn),
    .tx_en_i   (tx_prbs_en),
    .tx_data_o (prbs_tx_data),

    // RX PRBS checker
    .rx_clk_i  (cphy_rx_pcs_clk),
    .rx_rstn_i (rx_link_rstn),
    .rx_en_i   (rx_prbs_en),
    .rx_data_i (prbs_rx_data),
    .lock_o    (prbs_lock)
);

// -----------------------------------------------------------------------------
// Pass condition
// -----------------------------------------------------------------------------
wire link_pass_now;

assign link_pass_now = rx_link_rstn
                     & cphy_ready
                     & cphy_signal_detect
                     & cphy_rx_cdr_lock
                     & cphy_k_lock
                     & cphy_word_align_link
                     & rx_8b10b_no_err
                     & prbs_lock;

// LED 用实时 prbs_lock；如果想肉眼保持通过状态，可以改成 prbs_lock_seen。
// assign led = prbs_lock;

//60K板子此led低电平才亮
assign led = ~prbs_lock;

// -----------------------------------------------------------------------------
// Debug counters / sticky flags
// -----------------------------------------------------------------------------
reg [31:0] tx_wr_cnt;
reg [31:0] tx_data_cnt;
reg [31:0] tx_k_cnt;
reg        tx_afull_seen;
reg        tx_full_seen;

reg [31:0] rx_read_cnt;
reg [31:0] rx_valid_cnt;
reg [31:0] rx_data_cnt;
reg [31:0] rx_k285_cnt;
reg [31:0] rx_err_cnt;
reg [31:0] rx_unexpected_cnt;

reg [63:0] rx_last_code;
reg [7:0]  rx_last_k;
reg [7:0]  rx_last_disp_err;
reg [7:0]  rx_last_dec_err;

reg        prbs_lock_seen;
reg        link_pass_seen;
reg        rx_valid_seen;
reg        cdr_lock_seen;
reg        ready_seen;
reg        signal_detect_seen;
reg        k_lock_seen;
reg        word_align_seen;
reg        disp_err_seen;
reg        dec_err_seen;
reg        rx_unexpected_seen;
reg        rx_empty_seen;
reg        rx_aempty_seen;
reg        rx_activity_toggle;

always @(posedge cphy_tx_pcs_clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_wr_cnt     <= 32'd0;
        tx_data_cnt   <= 32'd0;
        tx_k_cnt      <= 32'd0;
        tx_afull_seen <= 1'b0;
        tx_full_seen  <= 1'b0;
    end else begin
        if (cphy_tx_fifo_wren_i) begin
            tx_wr_cnt <= tx_wr_cnt + 32'd1;

            if (tx_send_k_word)
                tx_k_cnt <= tx_k_cnt + 32'd1;
            else
                tx_data_cnt <= tx_data_cnt + 32'd1;
        end

        if (cphy_tx_fifo_afull)
            tx_afull_seen <= 1'b1;

        if (cphy_tx_fifo_full)
            tx_full_seen <= 1'b1;
    end
end

always @(posedge cphy_rx_pcs_clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_read_cnt        <= 32'd0;
        rx_valid_cnt       <= 32'd0;
        rx_data_cnt        <= 32'd0;
        rx_k285_cnt        <= 32'd0;
        rx_err_cnt         <= 32'd0;
        rx_unexpected_cnt  <= 32'd0;

        rx_last_code       <= 64'd0;
        rx_last_k          <= 8'd0;
        rx_last_disp_err   <= 8'd0;
        rx_last_dec_err    <= 8'd0;

        prbs_lock_seen     <= 1'b0;
        link_pass_seen     <= 1'b0;
        rx_valid_seen      <= 1'b0;
        cdr_lock_seen      <= 1'b0;
        ready_seen         <= 1'b0;
        signal_detect_seen <= 1'b0;
        k_lock_seen        <= 1'b0;
        word_align_seen    <= 1'b0;
        disp_err_seen      <= 1'b0;
        dec_err_seen       <= 1'b0;
        rx_unexpected_seen <= 1'b0;
        rx_empty_seen      <= 1'b0;
        rx_aempty_seen     <= 1'b0;
        rx_activity_toggle <= 1'b0;
    end else begin
        if (cphy_rx_fifo_rden_i)
            rx_read_cnt <= rx_read_cnt + 32'd1;

        if (cphy_rx_valid) begin
            rx_valid_cnt       <= rx_valid_cnt + 32'd1;
            rx_valid_seen      <= 1'b1;
            rx_activity_toggle <= ~rx_activity_toggle;

            rx_last_code       <= rx_code;
            rx_last_k          <= rx_k;
            rx_last_disp_err   <= rx_disp_err;
            rx_last_dec_err    <= rx_dec_err;
        end

        if (rx_is_data_word)
            rx_data_cnt <= rx_data_cnt + 32'd1;

        if (rx_is_valid_k_word)
            rx_k285_cnt <= rx_k285_cnt + 32'd1;

        if (cphy_rx_valid && !rx_8b10b_no_err)
            rx_err_cnt <= rx_err_cnt + 32'd1;

        if (rx_unexpected_word) begin
            rx_unexpected_cnt  <= rx_unexpected_cnt + 32'd1;
            rx_unexpected_seen <= 1'b1;
        end

        if (prbs_lock)
            prbs_lock_seen <= 1'b1;

        if (link_pass_now)
            link_pass_seen <= 1'b1;

        if (cphy_rx_cdr_lock)
            cdr_lock_seen <= 1'b1;

        if (cphy_ready)
            ready_seen <= 1'b1;

        if (cphy_signal_detect)
            signal_detect_seen <= 1'b1;

        if (cphy_k_lock)
            k_lock_seen <= 1'b1;

        if (cphy_word_align_link)
            word_align_seen <= 1'b1;

        if (|rx_disp_err)
            disp_err_seen <= 1'b1;

        if (|rx_dec_err)
            dec_err_seen <= 1'b1;

        if (cphy_rx_fifo_empty)
            rx_empty_seen <= 1'b1;

        if (cphy_rx_fifo_aempty)
            rx_aempty_seen <= 1'b1;
    end
end

// -----------------------------------------------------------------------------
// 50MHz heartbeat
// -----------------------------------------------------------------------------
reg [25:0] hb_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        hb_cnt <= 26'd0;
    else
        hb_cnt <= hb_cnt + 26'd1;
end

// -----------------------------------------------------------------------------
// GAO/ILA probe wires. Search prefix: ila8b10b_
// -----------------------------------------------------------------------------
wire [31:0] ila8b10b_top_version;
wire        ila8b10b_clk_heartbeat;

wire        ila8b10b_pll_lock;
wire        ila8b10b_ready;
wire        ila8b10b_signal_detect;
wire        ila8b10b_rx_cdr_lock;
wire        ila8b10b_k_lock;
wire        ila8b10b_word_align_link;

wire        ila8b10b_tx_link_rstn;
wire        ila8b10b_rx_link_rstn;

wire        ila8b10b_tx_fifo_wren;
wire [79:0] ila8b10b_tx_data;
wire [63:0] ila8b10b_tx_code;
wire [7:0]  ila8b10b_tx_k;
wire        ila8b10b_tx_send_k_word;
wire        ila8b10b_tx_send_data_word;
wire [15:0] ila8b10b_tx_train_cnt;
wire [15:0] ila8b10b_tx_interval_cnt;
wire [4:0]  ila8b10b_tx_fifo_wrusewd;
wire        ila8b10b_tx_fifo_afull;
wire        ila8b10b_tx_fifo_full;

wire        ila8b10b_rx_fifo_rden;
wire [87:0] ila8b10b_rx_data;
wire [63:0] ila8b10b_rx_code;
wire [7:0]  ila8b10b_rx_k;
wire [7:0]  ila8b10b_rx_disp_err;
wire [7:0]  ila8b10b_rx_dec_err;
wire [4:0]  ila8b10b_rx_fifo_rdusewd;
wire        ila8b10b_rx_fifo_aempty;
wire        ila8b10b_rx_fifo_empty;
wire        ila8b10b_rx_valid;

wire        ila8b10b_rx_8b10b_no_err;
wire        ila8b10b_rx_all_k285;
wire        ila8b10b_rx_is_data_word;
wire        ila8b10b_rx_is_valid_k_word;
wire        ila8b10b_rx_unexpected_word;
wire        ila8b10b_tx_prbs_en;
wire        ila8b10b_rx_prbs_en;
wire [63:0] ila8b10b_prbs_tx_data;
wire [63:0] ila8b10b_prbs_rx_data;
wire        ila8b10b_prbs_lock;
wire        ila8b10b_link_pass_now;
wire        ila8b10b_link_pass_seen;

wire [31:0] ila8b10b_tx_wr_cnt;
wire [31:0] ila8b10b_tx_data_cnt;
wire [31:0] ila8b10b_tx_k_cnt;
wire [31:0] ila8b10b_rx_read_cnt;
wire [31:0] ila8b10b_rx_valid_cnt;
wire [31:0] ila8b10b_rx_data_cnt;
wire [31:0] ila8b10b_rx_k285_cnt;
wire [31:0] ila8b10b_rx_err_cnt;
wire [31:0] ila8b10b_rx_unexpected_cnt;

wire [63:0] ila8b10b_rx_last_code;
wire [7:0]  ila8b10b_rx_last_k;
wire [7:0]  ila8b10b_rx_last_disp_err;
wire [7:0]  ila8b10b_rx_last_dec_err;

wire        ila8b10b_prbs_lock_seen;
wire        ila8b10b_rx_valid_seen;
wire        ila8b10b_cdr_lock_seen;
wire        ila8b10b_ready_seen;
wire        ila8b10b_signal_detect_seen;
wire        ila8b10b_k_lock_seen;
wire        ila8b10b_word_align_seen;
wire        ila8b10b_disp_err_seen;
wire        ila8b10b_dec_err_seen;
wire        ila8b10b_rx_unexpected_seen;
wire        ila8b10b_tx_afull_seen;
wire        ila8b10b_tx_full_seen;
wire        ila8b10b_rx_empty_seen;
wire        ila8b10b_rx_aempty_seen;
wire        ila8b10b_rx_activity_toggle;

assign ila8b10b_top_version        = TOP_VERSION;
assign ila8b10b_clk_heartbeat      = hb_cnt[25];

assign ila8b10b_pll_lock           = cphy_pll_lock;
assign ila8b10b_ready              = cphy_ready;
assign ila8b10b_signal_detect      = cphy_signal_detect;
assign ila8b10b_rx_cdr_lock        = cphy_rx_cdr_lock;
assign ila8b10b_k_lock             = cphy_k_lock;
assign ila8b10b_word_align_link    = cphy_word_align_link;

assign ila8b10b_tx_link_rstn       = tx_link_rstn;
assign ila8b10b_rx_link_rstn       = rx_link_rstn;

assign ila8b10b_tx_fifo_wren       = cphy_tx_fifo_wren_i;
assign ila8b10b_tx_data            = cphy_tx_data_i;
assign ila8b10b_tx_code            = tx_code;
assign ila8b10b_tx_k               = tx_k;
assign ila8b10b_tx_send_k_word     = tx_send_k_word;
assign ila8b10b_tx_send_data_word  = tx_send_data_word;
assign ila8b10b_tx_train_cnt       = tx_train_cnt;
assign ila8b10b_tx_interval_cnt    = tx_interval_cnt;
assign ila8b10b_tx_fifo_wrusewd    = cphy_tx_fifo_wrusewd;
assign ila8b10b_tx_fifo_afull      = cphy_tx_fifo_afull;
assign ila8b10b_tx_fifo_full       = cphy_tx_fifo_full;

assign ila8b10b_rx_fifo_rden       = cphy_rx_fifo_rden_i;
assign ila8b10b_rx_data            = cphy_rx_data;
assign ila8b10b_rx_code            = rx_code;
assign ila8b10b_rx_k               = rx_k;
assign ila8b10b_rx_disp_err        = rx_disp_err;
assign ila8b10b_rx_dec_err         = rx_dec_err;
assign ila8b10b_rx_fifo_rdusewd    = cphy_rx_fifo_rdusewd;
assign ila8b10b_rx_fifo_aempty     = cphy_rx_fifo_aempty;
assign ila8b10b_rx_fifo_empty      = cphy_rx_fifo_empty;
assign ila8b10b_rx_valid           = cphy_rx_valid;

assign ila8b10b_rx_8b10b_no_err    = rx_8b10b_no_err;
assign ila8b10b_rx_all_k285        = rx_all_k285;
assign ila8b10b_rx_is_data_word    = rx_is_data_word;
assign ila8b10b_rx_is_valid_k_word = rx_is_valid_k_word;
assign ila8b10b_rx_unexpected_word = rx_unexpected_word;
assign ila8b10b_tx_prbs_en         = tx_prbs_en;
assign ila8b10b_rx_prbs_en         = rx_prbs_en;
assign ila8b10b_prbs_tx_data       = prbs_tx_data;
assign ila8b10b_prbs_rx_data       = prbs_rx_data;
assign ila8b10b_prbs_lock          = prbs_lock;
assign ila8b10b_link_pass_now      = link_pass_now;
assign ila8b10b_link_pass_seen     = link_pass_seen;

assign ila8b10b_tx_wr_cnt          = tx_wr_cnt;
assign ila8b10b_tx_data_cnt        = tx_data_cnt;
assign ila8b10b_tx_k_cnt           = tx_k_cnt;
assign ila8b10b_rx_read_cnt        = rx_read_cnt;
assign ila8b10b_rx_valid_cnt       = rx_valid_cnt;
assign ila8b10b_rx_data_cnt        = rx_data_cnt;
assign ila8b10b_rx_k285_cnt        = rx_k285_cnt;
assign ila8b10b_rx_err_cnt         = rx_err_cnt;
assign ila8b10b_rx_unexpected_cnt  = rx_unexpected_cnt;

assign ila8b10b_rx_last_code       = rx_last_code;
assign ila8b10b_rx_last_k          = rx_last_k;
assign ila8b10b_rx_last_disp_err   = rx_last_disp_err;
assign ila8b10b_rx_last_dec_err    = rx_last_dec_err;

assign ila8b10b_prbs_lock_seen     = prbs_lock_seen;
assign ila8b10b_rx_valid_seen      = rx_valid_seen;
assign ila8b10b_cdr_lock_seen      = cdr_lock_seen;
assign ila8b10b_ready_seen         = ready_seen;
assign ila8b10b_signal_detect_seen = signal_detect_seen;
assign ila8b10b_k_lock_seen        = k_lock_seen;
assign ila8b10b_word_align_seen    = word_align_seen;
assign ila8b10b_disp_err_seen      = disp_err_seen;
assign ila8b10b_dec_err_seen       = dec_err_seen;
assign ila8b10b_rx_unexpected_seen = rx_unexpected_seen;
assign ila8b10b_tx_afull_seen      = tx_afull_seen;
assign ila8b10b_tx_full_seen       = tx_full_seen;
assign ila8b10b_rx_empty_seen      = rx_empty_seen;
assign ila8b10b_rx_aempty_seen     = rx_aempty_seen;
assign ila8b10b_rx_activity_toggle = rx_activity_toggle;

endmodule