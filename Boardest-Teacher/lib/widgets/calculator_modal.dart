import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CalculatorModal extends StatefulWidget {
  const CalculatorModal({super.key});

  @override
  State<CalculatorModal> createState() => _CalculatorModalState();
}

class _CalculatorModalState extends State<CalculatorModal> {
  String _expression = '';
  String _result = '0';

  void _onPress(String value) {
    setState(() {
      if (value == 'C') {
        _expression = '';
        _result = '0';
      } else if (value == 'DEL') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (value == '=') {
        _calculate();
      } else {
        // Prevent multiple consecutive operators
        final operators = ['+', '-', '*', '/', '%'];
        if (_expression.isNotEmpty &&
            operators.contains(value) &&
            operators.contains(_expression[_expression.length - 1])) {
          _expression = _expression.substring(0, _expression.length - 1) + value;
        } else {
          _expression += value;
        }
      }
    });
  }

  void _calculate() {
    if (_expression.isEmpty) return;
    try {
      // Basic expression parser
      final sanitized = _expression
          .replaceAll('×', '*')
          .replaceAll('÷', '/');
      
      final eval = _evaluateExpression(sanitized);
      
      setState(() {
        if (eval % 1 == 0) {
          _result = eval.toInt().toString();
        } else {
          _result = eval.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
        }
      });
    } catch (_) {
      setState(() {
        _result = 'Error';
      });
    }
  }

  double _evaluateExpression(String expr) {
    // Basic left-to-right calculation supporting operators
    final tokens = _tokenize(expr);
    if (tokens.isEmpty) return 0.0;

    // Apply multiply and divide first
    final List<dynamic> intermediate = [];
    int i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      if (token == '*' || token == '/' || token == '%') {
        final left = intermediate.removeLast() as double;
        final right = double.parse(tokens[i + 1]);
        if (token == '*') {
          intermediate.add(left * right);
        } else if (token == '/') {
          if (right == 0) throw Exception('Division by zero');
          intermediate.add(left / right);
        } else {
          if (right == 0) throw Exception('Modulo by zero');
          intermediate.add(left % right);
        }
        i += 2;
      } else {
        if (double.tryParse(token) != null) {
          intermediate.add(double.parse(token));
        } else {
          intermediate.add(token);
        }
        i++;
      }
    }

    // Apply add and subtract
    double total = intermediate[0] as double;
    int j = 1;
    while (j < intermediate.length) {
      final op = intermediate[j];
      final val = intermediate[j + 1] as double;
      if (op == '+') {
        total += val;
      } else if (op == '-') {
        total -= val;
      }
      j += 2;
    }

    return total;
  }

  List<String> _tokenize(String expr) {
    final List<String> tokens = [];
    String buffer = '';
    final operators = ['+', '-', '*', '/', '%'];

    for (int i = 0; i < expr.length; i++) {
      final char = expr[i];
      
      // Support negative numbers on start or after another operator
      if (char == '-' && (i == 0 || operators.contains(expr[i - 1]))) {
        buffer += char;
        continue;
      }

      if (operators.contains(char)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer);
          buffer = '';
        }
        tokens.add(char);
      } else {
        buffer += char;
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer);
    }
    return tokens;
  }

  Widget _buildButton(String label, {Color? color, Color? textColor}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onPress(label),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: color ?? Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textColor ?? Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 320,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      '인앱 계산기',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    centerTitle: true,
                    leading: Container(), // Hide back
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  
                  // Display Screen
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _expression.isEmpty ? ' ' : _expression,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              color: Colors.white60,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _result,
                            style: GoogleFonts.outfit(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Keyboard Grid
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildButton('C', color: Colors.redAccent.withValues(alpha: 0.2), textColor: Colors.redAccent),
                            _buildButton('DEL', color: Colors.orangeAccent.withValues(alpha: 0.2), textColor: Colors.orangeAccent),
                            _buildButton('%', textColor: Colors.cyanAccent),
                            _buildButton('÷', textColor: Colors.cyanAccent),
                          ],
                        ),
                        Row(
                          children: [
                            _buildButton('7'),
                            _buildButton('8'),
                            _buildButton('9'),
                            _buildButton('×', textColor: Colors.cyanAccent),
                          ],
                        ),
                        Row(
                          children: [
                            _buildButton('4'),
                            _buildButton('5'),
                            _buildButton('6'),
                            _buildButton('-', textColor: Colors.cyanAccent),
                          ],
                        ),
                        Row(
                          children: [
                            _buildButton('1'),
                            _buildButton('2'),
                            _buildButton('3'),
                            _buildButton('+', textColor: Colors.cyanAccent),
                          ],
                        ),
                        Row(
                          children: [
                            _buildButton('0'),
                            _buildButton('.'),
                            _buildButton('=', color: Colors.cyanAccent.withValues(alpha: 0.35), textColor: Colors.cyanAccent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
