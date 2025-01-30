module MVM #(
	parameter DATA_WIDTH = 8
	parameter ARR_WIDTH = 8
	parameter DEPTH = 8
)(
	input clk,
	input rst_n,
	input [DATA_WIDTH - 1:0]En,
	input Clr,
	input [DATA_WIDTH-1:0] B [DEPTH-1:0],
	input reg [DATA_WIDTH - 1:0]a[ARR_WIDTH-1:0][DEPTH - 1:0], //Data width * array width - 1
	output [DATA_WIDTH-1:0]result
);

localparam READ_MEM = 2'd0;
localparam FILL = 2'd1;
localparam EXEC = 2'd2;
localparam DONE = 2'd3;


//=======================================================
//  REG/WIRE declarations
//=======================================================

reg [1:0] state;
wire rst_n;


reg [31:0] address_index;
reg read_mem, mem_valid, mem_wait_request;
reg [63:0] read_data_mem;
mem_wrapper (
    .clk(clk),
    .reset_n(rst_n),
    .address(address_index),      // 32-bit address for 8 rows
    .read(read_mem),                // Read request
    .readdata(read_data_mem),     // 64-bit read data (one row)
    .readdatavalid(mem_valid),       // Data valid signal
    .waitrequest(mem_wait_request)          // Busy signal to indicate logic is processing
);

reg a_in, a_out [7:0]; //Loop through read_data_mem 8 times for each fifo. a_out only should be used once all fifos are filled. 
wire [7:0] full_a, empty_a, wren_a, rden_a;
FIFO iFa[7:0](
  .clk(clk),
  .rst_n(rst_n),
  .rden(rden_a),
  .wren(wren_a),
  .i_data(a_in),
  .o_data(a_out),
  .full(full_a),
  .empty(empty_a)
);
reg b_in, b_out [7:0]; // Loop through B to fill this fifo.
wire full_b, empty_b;
FIFO iFb(
  .clk(clk),
  .rst_n(rst_n),
  .rden(rden_b),
  .wren(wren),
  .i_data(b),
  .o_data(b_out),
  .full(full_b),
  .empty(empty_b)
);

reg [7:0] en;
wire [DATA_WIDTH*3-1:0] macout [7:0];
MAC iMAC[7:0] (
    .clk(clk),
    .rst_n(clk),
    .En(en),
    .Clr(Clr),
    .Ain(a_out),
    .Bin(b_out,
    .Cout(macout)

);

//=======================================================
//  Structural coding
//=======================================================

assign rst_n = KEY[0];
assign wren[0] = state == FILL;
assign wren[1] = wren[0];
assign rden[0] = state == EXEC;
assign rden[1] = rden[0];

integer j, i;

always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    state <= READ_MEM;
	address_index = 32'h0000;
	read_mem = 1'b0;
	 for (j=0; j<8; j=j+1) begin
	   Cout[j] <= {(DATA_WIDTH*3){1'b0}};
	 end
	   b_in <= {DATA_WIDTH{1'b0}};
	 for (j=0; j<8; j=j+1) begin
	   a_in[j] <= {DATA_WIDTH{1'b0}};
	 end
  end
  else begin
    case(state)
	   READ_MEM: 
		begin 
		read_mem <= 1'b1;
		if (mem_valid & ~mem_wait_request) //done reading from mem
		  state <= FILL:
	   FILL:
		begin
		if (full[7]) begin //last fifo has been filled
		    state <= EXEC;
		end
		else if (full[address_index / 64 -1]) begin
		    address_index <= address_index + 64;
		    state <= READ_MEM;
		end 
		  else begin
		  	// Memory needs to be loaded and stored in the fifos reg [31:0] address_index; reg read_mem, mem_valid, mem_wait_request; reg [63:0] read_data_mem;
			a_in[7:0] = read_data_mem[i:i+ 7];
			b_in[7:0] = 
			i++;
			wren_a[address_index / 64 -1] = 1'b1;
		  end
	   end	
		EXEC:
		begin
		  if (empty) begin
		    state <= DONE;
		  end
		end
		DONE:
		begin
		  result <= macout;
		end
	 endcase
  end
end



always_ff @(posedge clk, rst_n) begin

end









endmodule 
