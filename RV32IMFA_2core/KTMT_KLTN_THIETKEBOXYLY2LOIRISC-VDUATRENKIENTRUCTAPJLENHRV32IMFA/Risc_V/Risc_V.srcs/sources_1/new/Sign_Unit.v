module Sign_Unit  (A_s,B_s,Sign);
  input A_s,B_s; 
  output Sign;
  
  assign Sign=A_s^B_s;
  
endmodule