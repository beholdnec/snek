import 'dart:html';
import 'dart:math';
import 'dart:collection';

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

double dotProduct(Point a, Point b) {
  return a.x * b.x + a.y * b.y;
}

double crossProductMagnitude(Point a, Point b) {
  return a.x * b.y - a.y * b.x;
}

Point pointAtAngle(num angle) {
  return new Point(cos(angle), sin(angle));
}

Point randomPoint(num maxX, num maxY) {
  Random r = new Random();
  return new Point(r.nextDouble() * maxX, r.nextDouble() * maxY);
}

// Return squared distance from point p to line segment s1 -> s2. The squared
// distance is returned, as taking the square root is expensive and often not
// needed.
// Ref: <http://paulbourke.net/geometry/pointlineplane/>
double squaredDistancePointToLineSegment(Point p, Point s1, Point s2) {
  final double s1s2SquaredDistance = s1.squaredDistanceTo(s2);

  // If line segment is actually a point, compute distance between point and p.
  if (s1s2SquaredDistance <= 0) {
    return s1.squaredDistanceTo(p);
  }

  final Point s1s2 = s2 - s1;
  final Point s1p = p - s1;

  final double u = dotProduct(s1p, s1s2) / s1s2SquaredDistance;
  if (u <= 0) {
    return s1.squaredDistanceTo(p);
  } else if (u >= 1) {
    return s2.squaredDistanceTo(p);
  }

  return (s1 + s1s2 * u).squaredDistanceTo(p);
}

// Return whether point p with heading v will collide with line segment s1 ->
// s2. To be precise, this functions checks whether the distance between p and
// line segment s1 -> s2 decreases as p travels with velocity v.
bool willCollide(Point p, Point v, Point s1, Point s2) {
  final Point s1s2 = s2 - s1;
  final Point s1p = p - s1;
  final Point s2p = p - s2;

  final double s1s2SquaredDistance = s1.squaredDistanceTo(s2);

  if (s1s2SquaredDistance <= 0) {
    // Line segment is a point.

    // Return false if p is exactly at s1.
    if (s1p.x == 0 && s1p.y == 0) {
      return false;
    }

    // Return true if p is getting closer to s1.
    return dotProduct(v, s1p) < 0;
  }

  final double u = dotProduct(s1p, s1s2) / s1s2SquaredDistance;
  if (u <= 0) {
    // p is nearest to s1. Return true if p is getting closer to s1.
    return dotProduct(v, s1p) < 0;
  } else if (u >= 1) {
    // p is nearest to s2. Return true if p is getting closer to s2.
    return dotProduct(v, s2p) < 0;
  }

  return dotProduct(s1s2 * (dotProduct(v, s1s2) / s1s2SquaredDistance) - v,
    s1 + s1s2 * u - p) < 0;
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
  // frequency of game in ticks per second
  // Note this is frequency of physics and game logic, NOT frame rate
  // It is important for the game to tick at a rapid, constant rate, as doing
  // otherwise may cause physics glitches.
  static const int TICKS_PER_SECOND = 120;
  static const num TICK_PERIOD_MILLIS = 1000 / TICKS_PER_SECOND;
  // maximum number of ticks per call to _update (i.e. per frame)
  // If _update is called too slowly, the game will run in slow motion.
  static const int MAX_TICKS_PER_FRAME = 12;
  // number of segments in body when starting game
  static const int START_BODY_LENGTH = 100;
  // number of segments added to body upon eating food
  static const int BODY_PER_FOOD = 50;
  // diameter of food in pixels (for collision detection)
  static const num FOOD_DIAMETER = 20;
  // distance between head and body to be considered self-colliding
  static const num BODY_COLLIDE_DISTANCE = 8;

  // constants for drawing
  static const String HEAD_FILL_STYLE = 'LimeGreen';
  static const num HEAD_LENGTH = 20;
  static const num HEAD_WIDTH = 14;
  static const String EYE_FILL_STYLE = 'Teal';
  static const num EYE_LENGTH = 6;
  static const num EYE_WIDTH = 3;
  static const String BODY_STROKE_STYLE = 'LimeGreen';
  static const num BODY_WIDTH = 8;

  num _lastTimeStamp = 0;
  // if true, draw the canvas
  bool _needsDraw;

  // position of head in pixels
  Point _headPosition;
  // angle of head in degrees counter-clockwise from east
  num _headAngle;
  // maximum length of body in segments (points)
  int _bodyLength;
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
    _bodyLength = START_BODY_LENGTH;
    _bodyPoints = new List();
    _bodyPoints.insert(0, _headPosition);
    _placeFood();
    _needsDraw = true;
    _lastTimeStamp = window.performance.now();
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

  void _update(num timestamp) {
    int tickNum;
    for (tickNum = 0; tickNum < MAX_TICKS_PER_FRAME; ++tickNum) {
      final num delta = timestamp - _lastTimeStamp;
      if (delta < TICK_PERIOD_MILLIS) {
        break;
      }

      _tick(TICK_PERIOD_MILLIS);

      _lastTimeStamp += TICK_PERIOD_MILLIS;
    }

    // if too many ticks occurred, move game timestamp all the way up to current
    // timestamp
    if (tickNum >= MAX_TICKS_PER_FRAME) {
      _lastTimeStamp = timestamp;
    }
  }

  void _tick(num delta) {
    // rotate snake head
    num inputDirection = 0;
    if (keyboard.isPressed(KeyCode.LEFT) || keyboard.isPressed(KeyCode.A)) {
      inputDirection -= 1;
    }
    if (keyboard.isPressed(KeyCode.RIGHT) || keyboard.isPressed(KeyCode.D)) {
      inputDirection += 1;
    }
    _headAngle += inputDirection * _rotateSpeed * delta / 1000;
    _headAngle %= 360;

    // add new body point at head
    // Dart doesn't store a reference to _headPosition; instead, _headPosition
    // is cloned. Therefore, this is safe.
    _bodyPoints.insert(0, _headPosition);
    if (_bodyPoints.length > _bodyLength) {
      _bodyPoints.removeLast();
    }

    // move head forward
    final Point offset = pointAtAngle(_headAngle * PI / 180) * (_moveSpeed * delta / 1000);
    _headPosition += offset;

    // check for wall  or body collision
    if (_headPosition.x < 0 || _headPosition.y < 0 ||
      _headPosition.x >= canvas.width || _headPosition.y >= canvas.height ||
      _isSnakeSelfColliding()) {
      // out of bounds; reset the game
      // TODO: carefully ensure game state is cleaned up and reset; abort
      // the current update
      init();
    }
    // check for food collision
    else if (_headPosition.squaredDistanceTo(_foodPosition) <= (FOOD_DIAMETER/2)*(FOOD_DIAMETER/2)) {
      // collision detected; eat the food
      _bodyLength += BODY_PER_FOOD;
      _placeFood();
      // TODO: play animation of food disappearing / reappearing
    }

    _needsDraw = true;
  }

  bool _isSnakeSelfColliding() {
    if (_bodyPoints.length < 2) {
      return false;
    }

    final Point v = pointAtAngle(_headAngle * PI / 180);

    for (int i = 0; i < _bodyPoints.length - 2; ++i) {
      final Point s1 = _bodyPoints[i];
      final Point s2 = _bodyPoints[i+1];
      if (squaredDistancePointToLineSegment(_headPosition, s1, s2) <
        BODY_COLLIDE_DISTANCE*BODY_COLLIDE_DISTANCE &&
        willCollide(_headPosition, v, s1, s2)) {
        return true;
      }
    }

    return false;
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
    ctx..strokeStyle = BODY_STROKE_STYLE
      ..lineWidth = BODY_WIDTH
      ..lineCap = 'round'
      ..lineJoin = 'round'
      ..beginPath()
      ..moveTo(_headPosition.x, _headPosition.y);
    for (Point pt in _bodyPoints) {
      ctx..lineTo(pt.x, pt.y);
    }
    ctx..stroke();

    double headAngleRads = _headAngle * PI / 180;
    Point angleVector = new Point(cos(headAngleRads), sin(headAngleRads));
    Point angleVectorNormal = new Point(-angleVector.y, angleVector.x);

    // draw snake head
    ctx..fillStyle = HEAD_FILL_STYLE
      ..beginPath()
      ..ellipse(_headPosition.x, _headPosition.y, HEAD_LENGTH/2, HEAD_WIDTH/2,
        headAngleRads, 0, 2 * PI, true)
      ..fill();

    // draw snake eyes
    Point leftEyePosition = _headPosition + angleVectorNormal * (HEAD_WIDTH/2);
    Point rightEyePosition = _headPosition - angleVectorNormal * (HEAD_WIDTH/2);
    ctx..fillStyle = EYE_FILL_STYLE
      ..beginPath()
      ..ellipse(leftEyePosition.x, leftEyePosition.y, EYE_LENGTH/2, EYE_WIDTH/2,
        headAngleRads, 0, 2 * PI, true)
      ..fill()
      ..beginPath()
      ..ellipse(rightEyePosition.x, rightEyePosition.y, EYE_LENGTH/2, EYE_WIDTH/2,
        headAngleRads, 0, 2 * PI, true)
      ..fill();

    // draw text for testing
    // Point p = _headPosition;
    // Point s1 = new Point(canvas.width / 4, canvas.height / 4);
    // Point s2 = new Point(canvas.width * 3/4, canvas.height * 3/4);
    // ctx..strokeStyle = 'black'
    //   ..lineWidth = 1
    //   ..beginPath()
    //   ..moveTo(s1.x, s1.y)..lineTo(s2.x, s2.y)
    //   ..stroke();
    // double testDist = sqrt(squaredDistancePointToLineSegment(_headPosition, s1, s2));
    // final bool willCollide_ = willCollide(_headPosition, pointAtAngle(_headAngle * PI / 180),
    //   s1, s2);
    // final bool isColliding = willCollide_ && testDist < 8;
    // ctx..textAlign = 'left'
    //   ..textBaseline = 'top'
    //   ..fillText('Distance to diagonal: ' + testDist.toString(), 0, 0)
    //   ..fillText('Will collide: ' + willCollide_.toString(), 0, 16)
    //   ..fillText('Is colliding: ' + isColliding.toString(), 0, 32)
    //   ..fillText('Is snake self-colliding: ' + _isSnakeSelfColliding().toString(), 0, 48);
  }
}
