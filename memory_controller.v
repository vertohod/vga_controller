module memory_controller (
	input	 wire clk,							// 50Mz(20ns)
	input	 wire nreset,						// active low
	
	// interface
	input  wire	[23:0]addr,
	output reg  [2047:0]data_read,
	input  wire [8:0]data_read_size,	
	input  wire [2047:0]data_write,
	input  wire [8:0]data_write_size,	
	input  wire	request,
	input  wire	n_write_enable,			// 1 - read, 0 - write	
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

//reg [4:0]sequence_output[3:0];
//reg [4:0]sequence_handler[3:0];

reg [15:0]ram_data_write_buffer = 16'hzzzz;
assign ram_dq = ram_data_write_buffer;

localparam state_inhibit					= 4'd0;
localparam state_no_operation				= 4'd1;
localparam state_delay						= 4'd2;
localparam state_mode_register_set		= 4'd3;
localparam state_initialization_ready	= 4'd4;
localparam state_bank_active				= 4'd5;
localparam state_precharge					= 4'd6;
localparam state_precharge_all			= 4'd7;
localparam state_auto_refresh				= 4'd8;
localparam state_read						= 4'd9;
localparam state_write						= 4'd10;
localparam state_read_ready				= 4'd11;
localparam state_write_ready				= 4'd12;
localparam state_read_burst				= 4'd13;
localparam state_write_burst				= 4'd14;
localparam state_end							= 4'd15;

reg [3:0]sequence_actions_initialization[7:0];
initial begin
	sequence_actions_initialization[0] = state_inhibit;
	sequence_actions_initialization[1] = state_precharge_all;
	sequence_actions_initialization[2] = state_auto_refresh;
	sequence_actions_initialization[3] = state_auto_refresh;
	sequence_actions_initialization[4] = state_mode_register_set;
	sequence_actions_initialization[5] = state_initialization_ready;
	sequence_actions_initialization[6] = state_end;
	sequence_actions_initialization[7] = state_end;
end

reg [3:0]sequence_actions_read_newbank[7:0];
initial begin
	sequence_actions_read_newbank[0] = state_precharge;
	sequence_actions_read_newbank[1] = state_bank_active;
	sequence_actions_read_newbank[2] = state_read;
	sequence_actions_read_newbank[3] = state_read_ready;
	sequence_actions_read_newbank[4] = state_end;
	sequence_actions_read_newbank[5] = state_end;
	sequence_actions_read_newbank[6] = state_end;
	sequence_actions_read_newbank[7] = state_end;
end
 
reg [3:0]sequence_actions_write_newbank[7:0];
initial begin
	sequence_actions_write_newbank[0] = state_precharge;
	sequence_actions_write_newbank[1] = state_bank_active;
	sequence_actions_write_newbank[2] = state_write;
	sequence_actions_write_newbank[3] = state_write_ready;
	sequence_actions_write_newbank[4] = state_end;
	sequence_actions_write_newbank[5] = state_end;
	sequence_actions_write_newbank[6] = state_end;
	sequence_actions_write_newbank[7] = state_end;
end

reg [3:0]sequence_actions_read_samebank[7:0];
initial begin
	sequence_actions_read_samebank[0] = state_read;
	sequence_actions_read_samebank[1] = state_read_ready;
	sequence_actions_read_samebank[2] = state_end;
	sequence_actions_read_samebank[3] = state_end;
	sequence_actions_read_samebank[4] = state_end;
	sequence_actions_read_samebank[5] = state_end;
	sequence_actions_read_samebank[6] = state_end;
	sequence_actions_read_samebank[7] = state_end;
end

reg [3:0]sequence_actions_write_samebank[7:0];
initial begin
	sequence_actions_write_samebank[0] = state_write;
	sequence_actions_write_samebank[1] = state_write_ready;
	sequence_actions_write_samebank[2] = state_end;
	sequence_actions_write_samebank[3] = state_end;
	sequence_actions_write_samebank[4] = state_end;
	sequence_actions_write_samebank[5] = state_end;
	sequence_actions_write_samebank[6] = state_end;
	sequence_actions_write_samebank[7] = state_end;
end

reg [3:0]sequence_actions_read_burst[7:0];
initial begin
	sequence_actions_read_burst[0] = state_precharge;
	sequence_actions_read_burst[1] = state_mode_register_set;
	sequence_actions_read_burst[2] = state_bank_active;
	sequence_actions_read_burst[3] = state_read;
	sequence_actions_read_burst[4] = state_read_burst;
	sequence_actions_read_burst[5] = state_read_ready;
	sequence_actions_read_burst[6] = state_precharge;
	sequence_actions_read_burst[7] = state_end;
end

reg [3:0]sequence_actions_write_burst[7:0];
initial begin
	sequence_actions_write_burst[0] = state_precharge;
	sequence_actions_write_burst[1] = state_mode_register_set;
	sequence_actions_write_burst[2] = state_bank_active;
	sequence_actions_write_burst[3] = state_write;
	sequence_actions_write_burst[4] = state_write_burst;
	sequence_actions_write_burst[5] = state_write_ready;
	sequence_actions_write_burst[6] = state_precharge;
	sequence_actions_write_burst[7] = state_end;
end

integer read_data_counter;
reg [15:0]read_data_buffer[127:0];
always @(read_data_buffer) begin
	for (read_data_counter = 0; read_data_counter < 128; read_data_counter = read_data_counter + 1) begin
		data_read[read_data_counter * 16 +: 16] = read_data_buffer[read_data_counter];
	end
end
integer write_data_counter;
reg [15:0]write_data_buffer[127:0];
always @(data_write) begin
	for (write_data_counter = 0; write_data_counter < 128; write_data_counter = write_data_counter + 1) begin
		write_data_buffer[write_data_counter] = data_write[write_data_counter * 16 +: 16];
	end
end

reg [23:0]last_addr;

wire [1:0]bank;
wire [1:0]last_bank;
assign bank = addr[21:20];
assign last_bank = last_addr[21:20];

wire [11:0]row;
wire [11:0]last_row;
assign row = addr[19:8];
assign last_row = last_addr[19:8];

wire [7:0]column;
wire [7:0]last_column;
assign column = addr[7:0];
assign last_column = last_addr[7:0];

integer index = 0;
reg is_chip_initialized = 1'b0;
reg is_bank_active = 1'b0;

wire [3:0]state;
assign state = time_counter_result > 32'd0
	? state_delay
	: is_chip_initialized
		? n_write_enable
			? data_read_size > 9'd1
				? sequence_actions_read_burst[index]
				: bank == last_bank && row == last_row
					? sequence_actions_read_samebank[index]
					: sequence_actions_read_newbank[index]
			: data_read_size > 9'd1
				? sequence_actions_write_burst[index]
				: bank == last_bank && row == last_row
					? sequence_actions_write_samebank[index]
					: sequence_actions_write_newbank[index]
		: sequence_actions_initialization[index];

wire [3:0]next_state;
assign next_state =  time_counter_result > 32'd0
	? state_delay
	: is_chip_initialized
		? n_write_enable
			? data_read_size > 9'd1
				? sequence_actions_read_burst[index + 1]
				: bank == last_bank && row == last_row
					? sequence_actions_read_samebank[index + 1]
					: sequence_actions_read_newbank[index + 1]
			: data_read_size > 9'd1
				? sequence_actions_write_burst[index + 1]
				: bank == last_bank && row == last_row
					? sequence_actions_write_samebank[index + 1]
					: sequence_actions_write_newbank[index + 1]
		: sequence_actions_initialization[index + 1];

reg local_data_ready;
reg local_save_ready;
assign data_ready = local_data_ready && request;
assign save_ready = local_save_ready && request;
assign busy = ~is_chip_initialized || index > 0;

wire command_clk;
assign command_clk = ~clk;
assign ram_clk = clk;

reg [31:0]time_counter = 32'd0;
wire [31:0]time_counter_result;
assign time_counter_result = time_counter > DELAY_tMIN ? time_counter - DELAY_tMIN : 32'd0;
						
reg dqm_buffer = 1'b0;
assign ram_udqm = dqm_buffer;
assign ram_ldqm = dqm_buffer;
reg [8:0]read_write_counter = 9'd0;						

always @(posedge command_clk) begin
	if (nreset) begin
		if (local_data_ready) begin
			local_data_ready <= 1'b0;
		end
		if (local_save_ready) begin
			local_save_ready <= 1'b0;
		end
		if (is_chip_initialized && ~request && index == 0) begin
			ram_command_register <= command_no_operation;
		end else if (state == state_delay) begin
			ram_command_register <= command_no_operation;
			time_counter <= time_counter_result;
		end else begin
			case(state)
				state_inhibit: begin
					ram_command_register <= command_inhibit;
					time_counter <= DELEY_tBEFORINIT;
				end
				state_mode_register_set: begin
					ram_command_register <= command_mode_register_set;
					{ram_ba1, ram_ba0, ram_addr} <= mode_register;
					time_counter <= DELAY_tMRD;
				end
				state_initialization_ready: begin
					is_chip_initialized <= 1'b1;
				end
				state_bank_active: begin
					ram_command_register <= command_bank_active;
					is_bank_active <= 1'b1;
					ram_ba1 <= bank[1];
					ram_ba0 <= bank[0];
					ram_addr[11:0] <= row;
					time_counter <= DELAY_tRP;
				end
				state_precharge: begin
					if (is_bank_active) begin
						ram_command_register <= command_precharge;
						ram_ba1 <= last_bank[1];
						ram_ba0 <= last_bank[0];
						ram_addr[11:0] <= {1'd0, precharge_10ap_selected, 9'd0};
						is_bank_active <= 1'b0;
						time_counter <= DELAY_tRCD;
					end
				end
				state_precharge_all: begin
					ram_command_register <= command_precharge;
					ram_addr[11:0] <= {1'd0, precharge_10ap_all, 9'd0};
					time_counter <= DELAY_tRP;
				end
				state_auto_refresh: begin
					ram_command_register <= command_auto_refresh;
					time_counter <= DELAY_tRFC;
				end
				state_read: begin
					ram_command_register <= command_read;
					ram_ba1 <= bank[1];
					ram_ba0 <= bank[0];
					ram_addr[11:0] <= {1'b0, read_write_a10ap, 2'b00, column};
					time_counter <= DELAY_tPROZ2;
				end
				state_write: begin
					ram_command_register <= command_write;
					ram_ba1 <= bank[1];
					ram_ba0 <= bank[0];
					ram_addr[11:0] <= {1'b0, read_write_a10ap, 2'b00, column};
					ram_data_write_buffer <= write_data_buffer[read_write_counter]; // read_write_counter should be zero always
				end
				state_read_ready: begin
					ram_command_register <= command_no_operation;
					read_data_buffer[read_write_counter] <= ram_dq; // read_write_counter should be data_read_size at burst mode
					local_data_ready <= 1'b1;
				end
				state_write_ready: begin
					ram_command_register <= command_no_operation;
					ram_data_write_buffer <= 16'hzzzz;
					local_save_ready <= 1'b1;
				end
				state_read_burst: begin
					ram_command_register <= command_no_operation;
					read_data_buffer[read_write_counter] <= ram_dq;
				end
				state_write_burst: begin
					ram_command_register <= command_no_operation;
					ram_data_write_buffer <= write_data_buffer[read_write_counter];
				end
			endcase
			if (state == state_write) begin
				read_write_counter <= read_write_counter + 9'd1;
			end
			if ((state == state_read_burst && read_write_counter + 9'd1 < data_read_size)
				|| (state == state_write_burst && read_write_counter + 9'd1 < data_write_size)) begin
				read_write_counter <= read_write_counter + 9'd1;
			end else if (next_state == state_end) begin
				last_addr <= addr;
				index <= 0;
				read_write_counter <= 9'd0;
			end else index <= index + 1;
		end
	end else begin
		is_chip_initialized <= 1'b0;
		ram_data_write_buffer <= 16'hzzzz;
		time_counter <= 32'd0;
		index <= 0;
		is_bank_active <= 1'b0;
	end
end
endmodule
