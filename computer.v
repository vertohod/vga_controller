module computer (
	// clock
	input wire clk50M,		// 50 MHz (20ns)
	input wire nreset,
	input wire key3,
	input wire key4,
	output wire led1,
	
	// vga
	output wire vga_hsync,
	output wire vga_vsync,
	output wire [2:0]vga_rgb,
	
	// ram
	output wire ram_clk,
	output wire ram_cke,
	output wire ram_ncs,
	output wire ram_ba0,
	output wire ram_ba1,
	output wire [11:0]ram_addr,
	output wire ram_nras,
	output wire ram_ncas,
	output wire ram_nwe,
	output wire ram_udqm,
	output wire ram_ldqm,	
	inout wire [15:0]ram_dq	
);

reg clk25M;
always @(posedge clk50M) clk25M <= ~clk25M;

reg clk10K;
integer counter1250 = 0;
always @(posedge clk25M) begin
	counter1250 <= counter1250 == 1249 ? 0 : counter1250 + 1;
	clk10K <= counter1250 == 0 ? ~clk10K : clk10K;
end

reg clk1K;
integer counter5 = 0;
always @(posedge clk10K) begin
	counter5 <= counter5 == 4 ? 0 : counter5 + 1;
	clk1K <= counter5 == 0 ? ~clk1K : clk1K;
end

reg clk1H;
integer counter5000 = 0;
always @(posedge clk10K) begin
	counter5000 <= counter5000 == 4999 ? 0 : counter5000 + 1;
	clk1H <= counter5000 == 0 ? ~clk1H : clk1H;
end
assign led1 = clk1H;

// local bus
wire [23:0]bus_addr;
wire [2047:0]bus_data_read;
wire [2047:0]bus_data_write;
reg bus_ram_request = 1'b0;

localparam ram_read = 1'b1;
localparam ram_write = 1'b0;
reg bus_n_write_enable = 1'b1; // 1 - read, 0 - write

reg [3:0]rgb_data = 4'b0000;
wire ram_data_ready;
wire ram_save_ready;
wire ram_busy;

reg [2:0]value = 3'b000;
reg [23:0]addr_is_written = 24'd0;
reg [23:0]addr_write_buffer = 24'd0;
localparam pixel_amount_on_screen = 24'd76799;
always @(posedge clk10K) begin
	if (~nreset) begin
		addr_write_buffer <= 24'd0;
		value <= 3'b000;
	end else begin
		if (addr_write_buffer == pixel_amount_on_screen) begin
			addr_write_buffer <= 24'd0;
			value <= value + 3'd1;
		end else if (addr_is_written == addr_write_buffer) begin
			addr_write_buffer <= addr_write_buffer + 24'd1;
		end
	end
end

wire vint;
wire is_visible_array;

video_controller vc(
	.clk25M(clk25M),
	.rgb_data(rgb_data),
	.vint(vint),
	.is_visible_array(is_visible_array),
	.vga_hsync(vga_hsync),
	.vga_vsync(vga_vsync),
	.vga_rgb(vga_rgb));
	
memory_controller mc(
	.clk(clk50M),
	.nreset(nreset),
	.addr(bus_addr),
	.data_read(bus_data_read),
	.data_read_size(9'd1),
	.data_write(bus_data_write),
	.data_write_size(9'd1),
	.request(bus_ram_request),
	.n_write_enable(bus_n_write_enable),
	.data_ready(ram_data_ready),
	.save_ready(ram_save_ready),
	.busy(ram_busy),
	
	.ram_clk(ram_clk),
	.ram_cke(ram_cke),
	.ram_ncs(ram_ncs),
	.ram_ba0(ram_ba0),
	.ram_ba1(ram_ba1),
	.ram_addr(ram_addr),
	.ram_nras(ram_nras),
	.ram_ncas(ram_ncas),
	.ram_nwe(ram_nwe),
	.ram_udqm(ram_udqm),
	.ram_ldqm(ram_ldqm),
	.ram_dq(ram_dq));

reg [3:0]data4pixel1[3:0];
reg data_init1 = 1'b0;
reg [3:0]data4pixel2[3:0];
reg data_init2 = 1'b0;
reg is_current_first = 1'b1;

reg [2047:0]bus_data_write_buffer = 2048'd0;
reg [23:0]bus_addr_read_buffer = 24'd0;
reg [23:0]bus_addr_write_buffer = 24'd0;

assign bus_addr = bus_ram_request ? (bus_n_write_enable ? bus_addr_read_buffer : bus_addr_write_buffer) : 24'hzzzzzz;
assign bus_data_write = bus_data_write_buffer;

always @(posedge clk50M) begin
	if (ram_data_ready) begin
		if (~is_current_first || ~data_init1) begin
			data4pixel1[0] <= bus_data_read[3:0];
			data4pixel1[1] <= bus_data_read[7:4];
			data4pixel1[2] <= bus_data_read[11:8];
			data4pixel1[3] <= bus_data_read[15:12];
			data_init1 <= 1'b1;
		end else begin
			data4pixel2[0] <= bus_data_read[3:0];
			data4pixel2[1] <= bus_data_read[7:4];
			data4pixel2[2] <= bus_data_read[11:8];
			data4pixel2[3] <= bus_data_read[15:12];
			data_init2 <= 1'b1;
		end
		bus_ram_request = 1'b0;
	end
	if (ram_save_ready) begin
		bus_ram_request = 1'b0;
	end

	if (key3 && ~bus_ram_request && (data4length == 0 || ~data_init1 || ~data_init2)) begin
		bus_addr_read_buffer <= vint ? 24'd0 : (is_visible_array ? bus_addr_read_buffer + 24'd1 : bus_addr_read_buffer);
		bus_ram_request = 1'b1;
		bus_n_write_enable <= ram_read;
	end else if (key4 && ~bus_ram_request && data4length == 3 && addr_is_written != addr_write_buffer) begin
		bus_data_write_buffer[3:0] <= {1'b0, value};
		bus_data_write_buffer[7:4] <= {1'b0, value};
		bus_data_write_buffer[11:8] <= {1'b0, value};
		bus_data_write_buffer[15:12] <= {1'b0, value};
		bus_addr_write_buffer <= addr_write_buffer;
		addr_is_written <= addr_write_buffer;
		bus_ram_request = 1'b1;
		bus_n_write_enable <= ram_write;
	end
end

reg [3:0]data4pixel[255:0];
integer data4length = 0;
integer i;

always @(negedge clk25M) begin
	if (is_visible_array) begin
		rgb_data <= data4pixel[data4length];
		if (data4length == 0) begin
			is_current_first = ~is_current_first;
			if (is_current_first) begin
				for (i = 0; i < 256; i = i + 1) begin
					data4pixel[i] <= data4pixel1[i % 4];
				end
			end else begin
				for (i = 0; i < 256; i = i + 1) begin
					data4pixel[i] <= data4pixel2[i % 4];
				end
			end
			data4length <= 3;
		end else begin
			data4length <= data4length - 1;
		end
	end
end

endmodule
