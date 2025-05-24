module video_controller (
	input wire clk25M, // 25 MHz, 40ns
	input wire [3:0]rgb_data,
	output reg vint,
	output wire is_visible_array,
	
	output reg vga_hsync,
	output reg vga_vsync,
	output reg [2:0]vga_rgb
);

// settings VGA 648x480 60Hz
localparam hsync_pulse = 10'd95;
localparam hsync_end = 10'd799;
localparam hsync_act_begin = 10'd143;
localparam hsync_act_end = 10'd783;
localparam vsync_pulse = 10'd1;
localparam vsync_end = 10'd524;
localparam vsync_act_begin = 10'd34;
localparam vsync_act_end = 10'd514;

reg [9:0]hcount = 10'd0;
reg [9:0]vcount = 10'd0;
wire hcount_rst;
wire vcount_rst;

assign hcount_rst = (hcount == hsync_end);
assign vcount_rst = (vcount == vsync_end);

wire hact;
wire vact;
assign hact = ((hcount >= hsync_act_begin) && (hcount < hsync_act_end));
assign vact = ((vcount >= vsync_act_begin) && (vcount < vsync_act_end));
assign is_visible_array = hact && vact;

always @(posedge clk25M) begin
	if (hcount_rst) begin
		hcount <= 10'd0;
		vcount <= vcount + 10'd1;
	end else hcount <= hcount + 10'd1;
	if (vcount_rst) begin
		vcount <= 10'd0;
		vint <= 1'b1;
	end else vint <= 1'b0;

	if (hcount < hsync_pulse) vga_hsync <= 1'b0;
	else vga_hsync <= 1'b1;

	if (vcount < vsync_pulse) vga_vsync <= 1'b0;
	else vga_vsync <= 1'b1;

	if (is_visible_array) begin
		vga_rgb <= rgb_data[2:0];
	end else begin
		vga_rgb <= 3'b000;
	end
end
endmodule
