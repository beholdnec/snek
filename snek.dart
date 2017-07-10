import 'dart:html';
import 'dart:math';
import 'dart:collection';

CanvasElement canvas;
num virtualWidth = 300;
num virtualHeight = 300;
num dpiScaling = 1;
CanvasRenderingContext2D ctx;
Keyboard keyboard = new Keyboard();

void main() {
  canvas = querySelector('#canvas');
  virtualWidth = canvas.width;
  virtualHeight = canvas.height;

  // apply DPI scaling so game looks sharp on high-dpi screens.
  dpiScaling = window.devicePixelRatio;
  canvas.width = virtualWidth * dpiScaling;
  canvas.height = virtualHeight * dpiScaling;

  ctx = canvas.getContext('2d');

  new Game()..run();
}

void clear() {
  // this clears canvas and resets all canvas state
  canvas.width = canvas.width;

  // fill background with solid white
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

double randomBetween(double lo, double hi) {
  Random r = new Random();
  return lo + r.nextDouble() * (hi - lo);
}

Point randomPoint(Rectangle rect) {
  Random r = new Random();
  return new Point(rect.left + r.nextDouble() * rect.width,
    rect.top + r.nextDouble() * rect.height);
}

// tongue-blep animation controller
class BlepAnimationController {
  BlepAnimationController(double totalTime) {
    _currentTime = 0.0;
    _totalTime = totalTime;
  }

  void advance(double delta) {
    _currentTime += delta;
    if (_currentTime > _totalTime) {
      _currentTime = _totalTime;
    }
  }

  // BlepAnimationController provides this value to users.
  // Value goes up to 1.0 during the first half of total time, then it comes
  // back down.
  double get value {
    if (_currentTime < _totalTime / 2) {
      return _currentTime / (_totalTime / 2);
    } else {
      return (_totalTime - _currentTime) / (_totalTime / 2);
    }
  }

  bool get done {
    return _currentTime >= _totalTime;
  }

  double _currentTime;
  double _totalTime;
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
  static const String TONGUE_STROKE_STYLE = 'Red';
  static const num TONGUE_WIDTH = 2;
  static const int MAX_TONGUE_POINTS = 32;
  static const num TONGUE_LENGTH = 24;
  static const num TONGUE_SIDE_DISPLACEMENT = 2;

  // constants for animation
  static const num MIN_BLEP_DELAY_MS = 1000.0;
  static const num MAX_BLEP_DELAY_MS = 2000.0;
  static const num MIN_BLEP_TIME_MS = 200.0;
  static const num MAX_BLEP_TIME_MS = 750.0;
  static const num MIN_BLEP_SQUIGGLE = 0.5;
  static const num MAX_BLEP_SQUIGGLE = 3.0;

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
  // delay until blep
  double _blepDelay;
  // amount tongue squiggles when blepping
  double _blepSquiggle;
  // blep controller
  BlepAnimationController _blep = null;

  Game() {
    init();
  }

  void init() {
    _headPosition = new Point(virtualWidth / 2, virtualHeight / 2);
    _headAngle = 0;
    _moveSpeed = 100;
    _rotateSpeed = 360;
    _bodyLength = START_BODY_LENGTH;
    _bodyPoints = new List();
    _bodyPoints.insert(0, _headPosition);
    _placeFood();
    _startBlepDelay();
    _needsDraw = true;
    _lastTimeStamp = window.performance.now();
  }

  void _startBlepDelay() {
    _blepDelay = randomBetween(MIN_BLEP_DELAY_MS, MAX_BLEP_DELAY_MS);
    _blep = null;
  }

  void _triggerBlep() {
    _blepDelay = 0.0;
    _blepSquiggle = randomBetween(MIN_BLEP_SQUIGGLE, MAX_BLEP_SQUIGGLE);
    final double blepTime = randomBetween(MIN_BLEP_TIME_MS, MAX_BLEP_TIME_MS);
    _blep = new BlepAnimationController(blepTime);
  }

  void _placeFood() {
    Rectangle foodArea = new Rectangle.fromPoints(
      new Point(virtualWidth * 1/16, virtualHeight * 1/16),
      new Point(virtualWidth * 15/16, virtualHeight * 15/16));
    _foodPosition = randomPoint(foodArea);
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

    // drive tongue-blep animation
    if (_blepDelay > 0) {
      _blepDelay -= delta;
      if (_blepDelay <= 0) {
        _triggerBlep();
      }
    } else {
      _blep.advance(delta);
      if (_blep.done) {
        _startBlepDelay();
      }
    }

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
      _headPosition.x >= virtualWidth || _headPosition.y >= virtualHeight ||
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
    // clear will reset all drawing state, including transforms, styles, etc.
    clear();

    ctx..scale(dpiScaling, dpiScaling);

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

    // draw snake tongue
    if (_blep != null) {
      ctx..strokeStyle = TONGUE_STROKE_STYLE
        ..lineWidth = TONGUE_WIDTH
        ..beginPath()
        ..moveTo(_headPosition.x, _headPosition.y);
      final int numTonguePoints = (_blep.value * MAX_TONGUE_POINTS).toInt();
      for (int i = 0; i < numTonguePoints; ++i) {
        Point pt = _headPosition + angleVector * (HEAD_LENGTH / 2) +
          angleVector * (TONGUE_LENGTH * i / MAX_TONGUE_POINTS) +
          angleVectorNormal * TONGUE_SIDE_DISPLACEMENT *
            sin(_blepSquiggle * 2.0 * PI * i / MAX_TONGUE_POINTS);
        ctx..lineTo(pt.x, pt.y);
      }
      ctx..stroke();
    }

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
  }
}
