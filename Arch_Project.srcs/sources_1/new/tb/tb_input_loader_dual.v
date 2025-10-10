`timescale 1ns/1ps;
// ------------------------------------------------------------
// tb_input_loader_dual.v
// Testbench para input_loader_dual
// - Verifica carga de 8 nibbles en A y luego 8 nibbles en B.
// - Chequea loading_a, nibble_count, load_done y el valor final op_a/op_b.
// - Asegura que no cambie nada tras load_done a pesar de más pulsos.
// ------------------------------------------------------------
module tb_input_loader_dual;
  // DUT IO
  reg         clk;
  reg         rst;
  reg         load_btn;
  reg  [3:0]  nibbleA;
  reg  [3:0]  nibbleB;
  wire [31:0] op_a;
  wire [31:0] op_b;
  wire        load_done;
  wire        loading_a;
  wire [3:0]  nibble_count;

  // Instantiate DUT
  input_loader_dual dut (
    .clk(clk),
    .rst(rst),
    .load_btn(load_btn),
    .nibbleA(nibbleA),
    .nibbleB(nibbleB),
    .op_a(op_a),
    .op_b(op_b),
    .load_done(load_done),
    .loading_a(loading_a),
    .nibble_count(nibble_count)
  );

  // Clock 100 MHz
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Simple edge pulse for load_btn
  task press_btn;
    begin
      // botón en 0 por seguridad
      load_btn = 1'b0;
      @(posedge clk);
      load_btn = 1'b1; // flanco de subida
      @(posedge clk);
      load_btn = 1'b0;
      @(posedge clk);
    end
  endtask

  // Carga un nibble en A (usa nibbleA)
  task push_nibble_A(input [3:0] n);
    begin
      nibbleA = n;
      press_btn();
      // Después del flanco, DUT debería captar este nibble si loading_a=1
    end
  endtask

  // Carga un nibble en B (usa nibbleB)
  task push_nibble_B(input [3:0] n);
    begin
      nibbleB = n;
      press_btn();
      // Después del flanco, DUT debería captar este nibble si loading_a=0
    end
  endtask

  // Carga 8 nibbles para A en orden alto→bajo (primero el más significativo)
  task load_word_A(input [31:0] value);
    integer i;
    reg [31:0] tmp;
    begin
      tmp = value;
      // Primer nibble que se envía termina siendo el más significativo
      // Por lo tanto, enviamos nibbles MSB→LSB: [31:28], [27:24], ... [3:0]
      for (i=7; i>=0; i=i-1) begin
        push_nibble_A( tmp[ (i*4) +: 4 ] );
        // Comprobaciones básicas
        if (!loading_a && i>0) begin
          $display("[WARN] loading_a bajó antes de completar los 8 nibbles de A (i=%0d)", i);
        end
      end
    end
  endtask

  // Carga 8 nibbles para B en orden alto→bajo (primero el más significativo)
  task load_word_B(input [31:0] value);
    integer i;
    reg [31:0] tmp;
    begin
      tmp = value;
      for (i=7; i>=0; i=i-1) begin
        push_nibble_B( tmp[ (i*4) +: 4 ] );
        if (loading_a) begin
          $display("[WARN] loading_a volvió a 1 durante la carga de B (i=%0d)", i);
        end
      end
    end
  endtask

  // Prueba principal
  reg [31:0] expect_a;
  reg [31:0] expect_b;

  initial begin
    // Init
    load_btn = 1'b0;
    nibbleA  = 4'h0;
    nibbleB  = 4'h0;

    // Reset
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    // Espera estado inicial
    if (!loading_a) $fatal(1, "Esperaba loading_a=1 tras reset.");
    if (load_done)  $fatal(1, "Esperaba load_done=0 tras reset.");
    if (nibble_count != 4'd0) $fatal(1, "Esperaba nibble_count=0 tras reset.");

    // Valores a cargar
    // Usamos patrones fáciles de reconocer
    // A = 0xDEADBEEF ; B = 0x12345678
    expect_a = 32'hDEAD_BEEF;
    expect_b = 32'h1234_5678;

    $display("== Cargando A = 0x%08h ==", expect_a);
    load_word_A(expect_a);

    // Al completar 8 nibbles de A:
    @(posedge clk);
    if (loading_a !== 1'b0) $fatal(1, "Tras 8 nibbles, loading_a debería ser 0 (pasar a B).");
    if (nibble_count !== 4'd0) $fatal(1, "Tras cerrar A, nibble_count debería resetearse a 0.");
    if (op_a !== expect_a) begin
      $display("op_a = 0x%08h, esperado 0x%08h", op_a, expect_a);
      $fatal(1, "Valor final de op_a incorrecto.");
    end
    if (load_done) $fatal(1, "No debería estar load_done=1 todavía (falta B).");

    $display("== Cargando B = 0x%08h ==", expect_b);
    load_word_B(expect_b);

    // Al completar 8 nibbles de B:
    @(posedge clk);
    if (!load_done) $fatal(1, "Tras 8 nibbles de B, load_done debería ser 1.");
    if (op_b !== expect_b) begin
      $display("op_b = 0x%08h, esperado 0x%08h", op_b, expect_b);
      $fatal(1, "Valor final de op_b incorrecto.");
    end

    // Intentar más pulsos: no debe cambiar nada
    $display("== Enviando pulsos extra; los valores NO deben cambiar ==");
    press_btn();
    press_btn();
    @(posedge clk);
    if (op_a !== expect_a || op_b !== expect_b) begin
      $display("op_a = 0x%08h (exp 0x%08h), op_b = 0x%08h (exp 0x%08h)",
               op_a, expect_a, op_b, expect_b);
      $fatal(1, "Los operandos cambiaron después de load_done.");
    end

    $display(">>> TEST OK: input_loader_dual pasa todas las verificaciones.");
    #50 $finish;
  end

endmodule
