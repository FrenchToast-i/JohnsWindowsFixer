"""Material 3 Expressive morphing loading indicator.

A Material 3 Expressive "morphing blob": a 12-scallop cookie that morphs
through a rounded triangle, 8-star, 4-pill and 10-scallop keyframes while
rotating and gently breathing, over a soft radial glow.  It is idle by default
and only animates while the optimizer is working, matching the M3 Expressive
reference without adding ambient motion to the dashboard.

Exposed to QML as `M3ExpressiveIndicator` (import M3Loading 1.0).
"""

import math

from PyQt6.QtCore import (
    QEasingCurve,
    QPointF,
    QPropertyAnimation,
    QSequentialAnimationGroup,
    QPauseAnimation,
    Qt,
    pyqtProperty,
    pyqtSignal,
    pyqtSlot,
)
from PyQt6.QtGui import QBrush, QColor, QPainter, QPainterPath, QRadialGradient
from PyQt6.QtQuick import QQuickPaintedItem


class M3ExpressiveExactIndicator(QQuickPaintedItem):
    """Painted morphing-blob loader with configurable color."""

    runningChanged = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._num_samples = 120
        self._current_shape_idx = 0
        self._morph_progress = 0.0
        self._rotation_angle = 0.0
        self._pulse = 0.0
        self._running = False
        self._is_animating = False

        # The 5 keyframe silhouettes of the M3 Expressive indicator.
        self._keyframe_shapes = [
            self._create_12_scallop(),
            self._create_rounded_triangle(),
            self._create_8_star(),
            self._create_4_pill(),
            self._create_10_scallop(),
        ]

        self._indicator_color = QColor("#DFE278")

        # --- 1. Morph: fast springy snap, then a hold at the keyframe. ---
        self.morph_anim = QPropertyAnimation(self, b"morphProgress")
        self.morph_anim.setDuration(360)
        self.morph_anim.setStartValue(0.0)
        self.morph_anim.setEndValue(1.0)
        spring = QEasingCurve(QEasingCurve.Type.OutBack)
        spring.setOvershoot(1.6)
        self.morph_anim.setEasingCurve(spring)

        self.pause_anim = QPauseAnimation(520)

        self.morph_sequence = QSequentialAnimationGroup(self)
        self.morph_sequence.addAnimation(self.morph_anim)
        self.morph_sequence.addAnimation(self.pause_anim)
        self.morph_sequence.finished.connect(self._on_sequence_complete)

        # --- 2. Continuous rotation. ---
        self.rotate_anim = QPropertyAnimation(self, b"rotationAngle")
        self.rotate_anim.setDuration(6000)
        self.rotate_anim.setStartValue(0.0)
        self.rotate_anim.setEndValue(360.0)
        self.rotate_anim.setEasingCurve(QEasingCurve.Type.Linear)
        self.rotate_anim.setLoopCount(-1)

        # --- 3. Gentle "breathing" pulse for scale + glow intensity. ---
        pulse_up = QPropertyAnimation(self, b"pulse")
        pulse_up.setDuration(1500)
        pulse_up.setStartValue(0.0)
        pulse_up.setEndValue(1.0)
        pulse_up.setEasingCurve(QEasingCurve.Type.InOutSine)
        pulse_down = QPropertyAnimation(self, b"pulse")
        pulse_down.setDuration(1500)
        pulse_down.setStartValue(1.0)
        pulse_down.setEndValue(0.0)
        pulse_down.setEasingCurve(QEasingCurve.Type.InOutSine)

        self.pulse_sequence = QSequentialAnimationGroup(self)
        self.pulse_sequence.addAnimation(pulse_up)
        self.pulse_sequence.addAnimation(pulse_down)
        self.pulse_sequence.setLoopCount(-1)

        self.update()

        # The QML side owns the running state. Keeping the initial frame
        # still makes the idle Home screen calm and predictable.

    # ------------------------------------------------------------------ #
    # Public API (QML)
    # ------------------------------------------------------------------ #

    @pyqtSlot()
    def startAnimation(self):
        """Start (or resume) morphing, rotation and breathing."""
        if self._is_animating:
            return
        self._is_animating = True
        self.rotate_anim.start()
        self.morph_sequence.start()
        self.pulse_sequence.start()
        self.update()

    @pyqtSlot()
    def stopAnimation(self):
        """Freeze the current frame (does not reset to the cookie)."""
        self._is_animating = False
        self.rotate_anim.stop()
        self.morph_sequence.stop()
        self.pulse_sequence.stop()
        self.update()

    def _on_sequence_complete(self):
        self._current_shape_idx = (self._current_shape_idx + 1) % len(
            self._keyframe_shapes
        )
        self._morph_progress = 0.0
        if self._is_animating:
            self.morph_sequence.start()

    # ------------------------------------------------------------------ #
    # Properties
    # ------------------------------------------------------------------ #

    @pyqtProperty(bool, notify=runningChanged)
    def running(self):
        return self._running

    @running.setter
    def running(self, value):
        value = bool(value)
        if value == self._running:
            return
        self._running = value
        self.runningChanged.emit()
        if value:
            self.startAnimation()
        else:
            self.stopAnimation()

    def _get_indicator_color(self):
        return self._indicator_color

    def _set_indicator_color(self, value):
        color = QColor(value)
        if color != self._indicator_color:
            self._indicator_color = color
            self.update()

    indicatorColor = pyqtProperty(
        QColor, _get_indicator_color, _set_indicator_color
    )

    @pyqtProperty(float)
    def morphProgress(self):
        return self._morph_progress

    @morphProgress.setter
    def morphProgress(self, value):
        self._morph_progress = value
        self.update()

    @pyqtProperty(float)
    def rotationAngle(self):
        return self._rotation_angle

    @rotationAngle.setter
    def rotationAngle(self, value):
        self._rotation_angle = value
        self.update()

    @pyqtProperty(float)
    def pulse(self):
        return self._pulse

    @pulse.setter
    def pulse(self, value):
        self._pulse = value
        self.update()

    # ------------------------------------------------------------------ #
    # Shape generators
    # ------------------------------------------------------------------ #

    def _create_12_scallop(self):
        pts = []
        for i in range(self._num_samples):
            theta = (2.0 * math.pi * i) / self._num_samples
            r = 50.0 + 3.2 * math.cos(12 * theta)
            pts.append(QPointF(r * math.cos(theta), r * math.sin(theta)))
        return pts

    def _create_rounded_triangle(self):
        pts = []
        for i in range(self._num_samples):
            theta = (2.0 * math.pi * i) / self._num_samples
            r = 47.0 + 6.0 * math.cos(3 * theta + 0.3) + 2.0 * math.sin(2 * theta)
            pts.append(QPointF(r * math.cos(theta), r * math.sin(theta)))
        return pts

    def _create_8_star(self):
        pts = []
        for i in range(self._num_samples):
            theta = (2.0 * math.pi * i) / self._num_samples
            r = 49.0 + 7.5 * math.cos(8 * theta)
            pts.append(QPointF(r * math.cos(theta), r * math.sin(theta)))
        return pts

    def _create_4_pill(self):
        pts = []
        for i in range(self._num_samples):
            theta = (2.0 * math.pi * i) / self._num_samples
            r = 48.0 + 9.5 * math.cos(4 * theta)
            pts.append(QPointF(r * math.cos(theta), r * math.sin(theta)))
        return pts

    def _create_10_scallop(self):
        pts = []
        for i in range(self._num_samples):
            theta = (2.0 * math.pi * i) / self._num_samples
            r = 50.0 + 5.0 * math.cos(10 * theta)
            pts.append(QPointF(r * math.cos(theta), r * math.sin(theta)))
        return pts

    # ------------------------------------------------------------------ #
    # Path interpolation
    # ------------------------------------------------------------------ #

    def _build_smooth_path(self, points):
        path = QPainterPath()
        if not points:
            return path

        path.moveTo(points[0])
        n = len(points)

        for i in range(n):
            p0 = points[(i - 1) % n]
            p1 = points[i]
            p2 = points[(i + 1) % n]
            p3 = points[(i + 2) % n]

            ctrl1 = QPointF(
                p1.x() + (p2.x() - p0.x()) / 6.0,
                p1.y() + (p2.y() - p0.y()) / 6.0,
            )
            ctrl2 = QPointF(
                p2.x() - (p3.x() - p1.x()) / 6.0,
                p2.y() - (p3.y() - p1.y()) / 6.0,
            )

            path.cubicTo(ctrl1, ctrl2, p2)

        path.closeSubpath()
        return path

    def _interpolate(self, shape1, shape2, t):
        pts = []
        for p1, p2 in zip(shape1, shape2):
            x = (1.0 - t) * p1.x() + t * p2.x()
            y = (1.0 - t) * p1.y() + t * p2.y()
            pts.append(QPointF(x, y))
        return pts

    # ------------------------------------------------------------------ #
    # Painting
    # ------------------------------------------------------------------ #

    def paint(self, painter):
        w = self.width()
        h = self.height()
        if w <= 0 or h <= 0:
            return

        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        size = min(w, h)
        cx = w / 2.0
        cy = h / 2.0
        r = size / 2.0

        # 1. Soft radial glow (halo) behind the blob, breathing with pulse.
        glow = QRadialGradient(QPointF(cx, cy), r)
        center_c = QColor(self._indicator_color)
        center_c.setAlphaF(0.32 + 0.10 * self._pulse)
        mid_c = QColor(self._indicator_color)
        mid_c.setAlphaF(0.10 + 0.04 * self._pulse)
        edge_c = QColor(self._indicator_color)
        edge_c.setAlphaF(0.0)
        glow.setColorAt(0.0, center_c)
        glow.setColorAt(0.6, mid_c)
        glow.setColorAt(1.0, edge_c)

        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QBrush(glow))
        painter.drawEllipse(QPointF(cx, cy), r, r)

        # 2. The morphing blob, sized to fill most of the item and gently
        #    breathing in scale.
        painter.save()
        painter.translate(cx, cy)
        painter.rotate(self._rotation_angle)

        scale = (r * 0.80) / 57.0
        scale *= 1.0 + 0.05 * (self._pulse - 0.5)
        painter.scale(scale, scale)

        shape1 = self._keyframe_shapes[self._current_shape_idx]
        next_idx = (self._current_shape_idx + 1) % len(self._keyframe_shapes)
        shape2 = self._keyframe_shapes[next_idx]

        points = self._interpolate(shape1, shape2, self._morph_progress)
        path = self._build_smooth_path(points)

        painter.setBrush(self._indicator_color)
        painter.drawPath(path)
        painter.restore()
