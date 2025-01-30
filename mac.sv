module MAC #(
    parameter DATA_WIDTH = 8
) (
    input clk,
    input rst_n,
    input En,
    input Clr,
    input [DATA_WIDTH-1:0] Ain,
    input [DATA_WIDTH-1:0] Bin,
    output [DATA_WIDTH*3-1:0] Cout
);

    typedef enum reg {IDLE, ACC} state_t;
    state_t state, nxt_state;

    reg [DATA_WIDTH*3-1:0] CoutReg;
    logic acc;

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
	    state <= IDLE;
        end
        else if (Clr) begin
    	    state <= IDLE;
        end
        else begin
	    state <= nxt_state;
        end
    end

    always_comb begin
	acc = 0; // Default
	nxt_state = state;

	case (state)
	    default : if(En) begin
		nxt_state = ACC;
	    end

	    ACC : if(!En) begin
		nxt_state = IDLE;
	    end else begin
		acc = 1;
	    end
	endcase
    end

    always_ff @(posedge clk, negedge rst_n) begin
	if (!rst_n) begin
	    CoutReg <= '0;
	end else if (Clr) begin
	    CoutReg <= '0;
	end else if (acc) begin
	    CoutReg <= CoutReg + Ain*Bin;
	end
    end

    assign Cout = CoutReg;

endmodule