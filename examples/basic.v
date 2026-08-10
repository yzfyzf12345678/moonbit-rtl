module counter (
  input clk,
  input reset,
  output [7:0] value
);
  reg [7:0] state;
  always @(posedge clk or posedge reset) begin
    if (reset) state <= 0;
    else state <= state + 1;
  end
  assign value = state;
endmodule
