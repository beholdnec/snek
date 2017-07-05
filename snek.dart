import 'dart:html';
import 'dart:math';
import 'dart:collection';

const int CELL_SIZE = 10;

CanvasElement canvas;
CanvasRenderingContext2D ctx;
Keyboard keyboard = new Keyboard();

void main() {
  canvas = querySelector('#canvas');
  ctx = canvas.getContext('2d');

  new Game()..run();
}

void clear() {
  ctx..fillStyle = 'white'
    ..fillRect(0, 0, canvas.width, canvas.height);
}

Point randomPoint(num maxX, num maxY) {
  Random r = new Random();
  return new Point(r.nextDouble() * maxX, r.nextDouble() * maxY);
}

class Keyboard {
  HashMap<int, double> _keys = new HashMap<int, double>();

  Keyboard() {
    window.onKeyDown.listen((KeyboardEvent event) {
      if (!_keys.containsKey(event.keyCode)) {
        _keys[event.keyCode] = event.timeStamp;
      }
    });

    window.onKeyUp.listen((KeyboardEvent event) {
      _keys.remove(event.keyCode);
    });
  }

  bool isPressed(int keyCode) => _keys.containsKey(keyCode);
}

class Game {
  // smaller numbers make the game run faster
  // TODO: write a more sophisticated system for advancing frames
  static const num GAME_SPEED = 10;
  static const int START_BODY_POINTS = 100;

  num _lastTimeStamp = 0;
  // if true, draw the canvas
  bool _needsDraw;

  // position of head in pixels
  Point _headPosition;
  // angle of head in degrees counter-clockwise from east
  num _headAngle;
  List<Point> _bodyPoints;
  // speed of snake in pixels per second
  num _moveSpeed;
  // speed of rotation in degrees per second
  num _rotateSpeed;
  Point _foodPosition;

  Game() {
    init();
  }

  void init() {
    _headPosition = new Point(canvas.width / 2, canvas.height / 2);
    _headAngle = 0;
    _moveSpeed = 100;
    _rotateSpeed = 360;
    _bodyPoints = new List();
    for (int i = 0; i < START_BODY_POINTS; ++i) {
      _bodyPoints.add(_headPosition);
    }
    _placeFood();
    _needsDraw = true;
  }

  void _placeFood() {
    _foodPosition = randomPoint(canvas.width, canvas.height);
  }

  void run() {
    window.animationFrame.then(_onFrame);
  }

  void _onFrame(num delta) {
    _update(delta);

    if (_needsDraw) {
      _draw();
      _needsDraw = false;
    }

    // keep requesting frames
    run();
  }

  void _update(num delta) {
    final num diff = delta - _lastTimeStamp;

    if (diff > GAME_SPEED) {
      _lastTimeStamp = delta;

      // rotate snake head
      if (keyboard.isPressed(KeyCode.LEFT)) {
        _headAngle -= _rotateSpeed * diff / 1000;
      }
      else if (keyboard.isPressed(KeyCode.RIGHT)) {
        _headAngle += _rotateSpeed * diff / 1000;
      }

      // move head forward
      final Point offset = new Point(cos(_headAngle * PI / 180), sin(_headAngle * PI / 180))
        * (_moveSpeed * diff / 1000);
      _headPosition += offset;

      // TODO: clone, don't reference...
      _bodyPoints.insert(0, _headPosition);
      _bodyPoints.removeLast();

      _needsDraw = true;
    }
  }

  void _draw() {
    clear();

    // draw food (mouse)
    ctx..fillStyle = 'black'
      ..font = '16px sans-serif'
      ..textAlign = 'center'
      ..textBaseline = 'middle'
      ..fillText('🐁', _foodPosition.x, _foodPosition.y);

    // draw snake body
    // body is drawn before head so head appears above body
    ctx..strokeStyle = 'green'
      ..lineWidth = 5
      ..lineCap = 'round'
      ..lineJoin = 'round'
      ..beginPath()
      ..moveTo(_bodyPoints[0].x, _bodyPoints[0].y);
    for (Point pt in _bodyPoints.skip(1)) {
      ctx..lineTo(pt.x, pt.y);
    }
    ctx..stroke();

    // draw snake head
    ctx..fillStyle = 'green'
      ..beginPath()
      ..ellipse(_headPosition.x, _headPosition.y, 10, 5, _headAngle * PI / 180, 0, 2 * PI, true)
      ..fill();
  }
}
