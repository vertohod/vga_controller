module memory_controller (
	input	 wire clk,							// 50Mz(20ns)
	input	 wire nreset,						// active low
	
	// interface
	input  wire	[23:0]bus_addr,
	inout  reg	[15:0]bus_data_read,
	inout  wire	[15:0]bus_data_write,
	input  wire	bus_ram_request,
	input  wire	bus_n_write_enable,		// 1 - read, 0 - write	
	output wire	data_ready,
	output wire	save_ready,
	output wire busy,
	
	// ram-chip signals
	output wire	ram_clk,
	output wire	ram_cke,
	output wire	ram_ncs,
	output reg	ram_ba0,
	output reg	ram_ba1,
	output reg	[11:0]ram_addr,
	output wire	ram_nras,
	output wire	ram_ncas,
	output wire	ram_nwe,
	output wire	ram_udqm,
	output wire	ram_ldqm,
	
	inout	 wire [15:0]ram_dq
);

parameter	DELAY_tMIN			= 20000, // 20ns (50 MHz)
				// it was taken from datasheet for IC HY57V641620FTP-H 
				DELAY_tRC			= 63000,
				DELAY_tRRC			= 63000,
				DELAY_tRCD			= 20000,
				DELAY_tRAS			= 42000,
				DELAY_tRP			= 20000,
				DELAY_tRRD			= 15000,
				DELAY_tCCD			= DELAY_tMIN,
				DELAY_tDPL			= DELAY_tMIN * 2,
				DELAY_tDAL			= DELAY_tDPL + DELAY_tRP,
				DELAY_tPROZ3		= DELAY_tMIN * 3,
				DELAY_tPROZ2		= DELAY_tMIN * 2,
				DELAY_tMRD			= DELAY_tMIN * 2,
				DELAY_tTO			= 2500,	// Data-out Hold Time
				DELAY_tAS			= 1500,
				DELAY_tAH			= 800,
				DELAY_tREF			= 64000000,
				DELAY_tRFC			= 64000000,
				DELEY_tBEFORINIT	= 100000000;

localparam [2:0]burst_length_1 = 3'b000;
localparam [2:0]burst_length_2 = 3'b001;
localparam [2:0]burst_length_4 = 3'b010;
localparam [2:0]burst_length_8 = 3'b011;
localparam [2:0]burst_length_fullpage = 3'b111;

localparam bt_sequential = 1'b0;
localparam bt_interleave = 1'b1;

localparam [2:0]cas_latency_2 = 3'b010;
localparam [2:0]cas_latency_3 = 3'b011;

localparam op_code_brbw = 1'b0; // Burst Read and Burst Write
localparam op_code_brsw = 1'b1; // Burst Read and Single Write

reg [13:0]mode_register = {1'b0, 1'b0, 1'b0, 1'b0, op_code_brsw, 1'b0, 1'b0, cas_latency_2, bt_sequential, burst_length_1};

reg [4:0]ram_command_register;				
reg [4:0]last_command_register;				
localparam command_mode_register_set 	= 5'b10000;
localparam command_no_operation			= 5'b10111;
localparam command_inhibit					= 5'b11111;
localparam command_bank_active			= 5'b10011;
localparam command_read						= 5'b10101;
localparam command_write					= 5'b10100;
localparam command_precharge				= 5'b10010;
localparam command_burst_stop				= 5'b10110;
localparam command_auto_refresh			= 5'b10001;
localparam command_brsw						= 5'b10000; // Burst-Read-Single-Write / A9 ball High (Other balls OP code) / MRS Mode

assign {ram_cke, ram_ncs, ram_nras, ram_ncas, ram_nwe} = ram_command_register;				

localparam read_write_a10ap = 1'b0;								// 0 - read/write
localparam read_write_a10ap_with_autoprecharge = 1'b0;	// 1 - read/write with autoprecharge
localparam precharge_10ap_selected = 1'b0;					// 0 - selected bank
localparam precharge_10ap_all = 1'b1;							// 1 - all banks

reg [4:0]sequence_output[3:0];
reg [4:0]sequence_handler[3:0];

reg [15:0]ram_data_write_buffer = 16'hzzzz;
assign ram_dq = ram_data_write_buffer;

wire [7:0]current_status;
localparam status_delay						= 8'd0;
localparam status_bank_active				= 8'd1;
localparam status_precharge				= 8'd2;
localparam status_read						= 8'd3;
localparam status_write						= 8'd4;
localparam status_read_ready				= 8'd5;
localparam status_write_ready				= 8'd6;
localparam status_no_operation			= 8'd7;

reg local_data_ready;
reg local_save_ready;
assign data_ready = local_data_ready && bus_ram_request;
assign save_ready = local_save_ready && bus_ram_request;
assign busy = bus_ram_request || ~chip_initialized;

reg chip_initialized = 1'b0;

reg [3:0]step = 4'd0;

wire command_clk;
assign command_clk = ~clk;
assign ram_clk = clk;

reg [31:0]time_counter = 32'd0;
wire [31:0]time_counter_result;
assign time_counter_result = time_counter > DELAY_tMIN ? time_counter - DELAY_tMIN : 32'd0;

reg [13:0]last_row;
wire is_needed_precharge;
assign is_needed_precharge = last_row[13:0] != bus_addr[21:8];

wire process_begin;
assign process_begin = last_command_register == command_no_operation;

assign current_status = ~bus_ram_request
	? status_no_operation
	: time_counter_result > 32'd0
		? status_delay
		: process_begin && is_needed_precharge
			? status_precharge
			: last_command_register == command_precharge
				? status_bank_active
				: last_command_register == command_bank_active || (process_begin && ~is_needed_precharge)
					? (bus_n_write_enable ? status_read : status_write)
					: last_command_register == command_read
						? status_read_ready
						: last_command_register == command_write
							? status_write_ready
							: status_no_operation;						

reg dqm_buffer = 1'b0;
assign ram_udqm = dqm_buffer;
assign ram_ldqm = dqm_buffer;							
							
always @(posedge command_clk) begin
	if (~nreset) begin
		chip_initialized <= 1'b0;
		step <= 4'd0;
		bus_data_read <= 16'h0000;
		last_row[13:0] <= 14'd0;
		ram_data_write_buffer <= 16'hzzzz;
		time_counter <= 32'd0;
	end

	if (chip_initialized) begin
		// ------------------------------------------------------------
		// normal work
		// ------------------------------------------------------------
		case(current_status)
			status_no_operation: begin
				ram_command_register <= command_no_operation;
				last_command_register <= command_no_operation;
				local_data_ready <= 1'b0;
				local_save_ready <= 1'b0;
				ram_data_write_buffer <= 16'hzzzz;						
			end
			status_bank_active: begin
				ram_command_register <= command_bank_active;
				last_command_register <= command_bank_active;
				ram_ba1 <= bus_addr[21];
				ram_ba0 <= bus_addr[20];
				ram_addr[11:0] <= bus_addr[19:8];
				last_row[13:0] <= bus_addr[21:8];
				time_counter <= DELAY_tRP;
			end
			status_precharge: begin
				ram_command_register <= command_precharge;
				last_command_register <= command_precharge;
				ram_ba1 <= last_row[13];
				ram_ba0 <= last_row[12];
				ram_addr[11:0] <= {1'd0, precharge_10ap_selected, 9'd0};
				time_counter <= DELAY_tRCD;
			end
			status_read: begin
				ram_command_register <= command_read;
				last_command_register <= command_read;
				ram_ba1 <= bus_addr[21];
				ram_ba0 <= bus_addr[20];
				ram_addr[11:0] <= {1'b0, read_write_a10ap, 2'b00, bus_addr[7:0]};
				time_counter <= DELAY_tPROZ2;
			end
			status_write: begin
				ram_command_register <= command_write;
				last_command_register <= command_write;
				ram_ba1 <= bus_addr[21];
				ram_ba0 <= bus_addr[20];
				ram_addr[11:0] <= {1'b0, read_write_a10ap, 2'b00, bus_addr[7:0]};
				ram_data_write_buffer <= bus_data_write;
			end
			status_read_ready: begin
				ram_command_register <= command_no_operation;
				if (~local_data_ready) begin
					bus_data_read <= ram_dq;
					local_data_ready <= 1'b1;
				end
			end
			status_write_ready: begin
				ram_command_register <= command_no_operation;
				ram_data_write_buffer <= 16'hzzzz;
				local_save_ready <= 1'b1;
			end
			status_delay: begin
				ram_command_register <= command_no_operation;
				time_counter <= time_counter_result;
			end
		endcase
	end else begin
		// ------------------------------------------------------------
		// initialization
		// ------------------------------------------------------------
		if (time_counter_result > 32'd0) begin
			ram_command_register <= command_no_operation;
			time_counter <= time_counter_result;
		end else begin
			case(step)
				4'd0: begin
					ram_command_register <= command_inhibit;
					time_counter <= DELEY_tBEFORINIT;
				end
				4'd1: begin
					ram_command_register <= command_precharge;
					ram_addr[11:0] <= {1'd0, precharge_10ap_all, 9'd0};
					time_counter <= DELAY_tRP;
				end
				4'd2: begin
					ram_command_register <= command_auto_refresh;
					time_counter <= DELAY_tRFC;
				end
				4'd3: begin
					ram_command_register <= command_auto_refresh;
					time_counter <= DELAY_tRFC;
				end
				4'd4: begin
					ram_command_register <= command_mode_register_set;
					{ram_ba1, ram_ba0, ram_addr} <= mode_register;
					time_counter <= DELAY_tMRD;
				end
				4'd5: begin
					ram_command_register <= command_inhibit;
					chip_initialized <= 1'b1;
				end
				default: begin
				end
			endcase
			step <= step + 4'd1;
		end
	end
end
endmodule
