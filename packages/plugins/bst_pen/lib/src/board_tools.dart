/// 칠판 / PDF / PPT 공통 판서 도구 모드
enum ToolMode { pointer, pen, eraser, select, shape, insert, pan }

/// 판서 도형 종류
enum ShapeType { line, arrow, triangle, rectangle, circle, cube, cylinder }

/// TBP 입력 모드 (Pen=무조건 판서, Touch=무조건 통과, Smart=기본판서+꾹=터치)
enum TbpInputMode { pen, touch, smart }
