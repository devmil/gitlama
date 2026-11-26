#include <QtGui/QGuiApplication>
#include <QtGui/QMouseEvent>
#include <QtGui/QWheelEvent>
#include <QtGui/QWindow>
#include "graph_row.h"
#include "syntax_highlighter.h"
#include "text_formatter.h"

#include <QMetaMethod>
#include <QPainter>
#include <QPainterPath>
#include <QtQml/qqml.h>
#include <algorithm>
#include <cmath>

namespace gitlama {

namespace {

// GitLamaLayout (docs/design-system): the graph's geometry.
constexpr qreal laneWidth = 14;
constexpr qreal graphLaneOrigin = 9;
constexpr qreal graphCommitRadius = 4.5;
constexpr qreal graphRingStroke = 2;
constexpr qreal graphStrokeLit = 2.5;
constexpr qreal graphHeadInnerRadius = 4;
constexpr qreal graphHeadOuterRadius = 7;
constexpr qreal graphHeadOuterStroke = 1.5;
constexpr qreal graphMergeDotRadius = 1.75;
constexpr qreal graphDash = 2.2;
constexpr qreal graphBoundarySquare = 7;
constexpr qreal graphBoundaryStroke = 1.5;
// GitLamaOpacity.unlit
constexpr qreal unlitOpacity = 0.3;

// The row's node shapes, as Rust names them.
enum Shape { Commit, Merge, Boundary, Graft, Replace, Wip, WipConflict, Stash };
// Segment kinds.
enum Kind { Straight, Join, MergeKind, Octopus, BoundaryKind, Missing, CollapsedMerge };

QColor withAlpha(QColor color, qreal alpha)
{
    color.setAlphaF(color.alphaF() * alpha);
    return color;
}

void drawDashedCircle(QPainter *painter, QPointF center, qreal radius, const QColor &color,
                      qreal gapFactor = 1, qreal strokeWidth = graphRingStroke)
{
    QPen pen(color, strokeWidth);
    pen.setCapStyle(Qt::RoundCap);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    if (gapFactor <= 0) {
        painter->drawEllipse(center, radius, radius);
        return;
    }
    const qreal circumference = 2 * M_PI * radius;
    // A shrinking gap closes the dashes into a ring (NH-1).
    const qreal dash = graphDash + graphDash * (1 - gapFactor);
    const QRectF bounds(center.x() - radius, center.y() - radius, radius * 2, radius * 2);
    for (qreal position = 0; position < circumference; position += graphDash * 2) {
        // QPainter angles are in 1/16 degrees, counter-clockwise; the dash
        // pattern runs clockwise from the x axis.
        const qreal start = -(position / radius) * 180 / M_PI;
        const qreal span = -(dash / radius) * 180 / M_PI;
        painter->drawArc(bounds, int(std::round(start * 16)), int(std::round(span * 16)));
    }
}

} // namespace

GraphRow::GraphRow(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &GraphRow::changed, this, [this] { update(); });
}

qreal GraphRow::laneX(int lane)
{
    return graphLaneOrigin + lane * laneWidth;
}

GraphRow::Lighting GraphRow::currentLighting() const
{
    Lighting state { lightingActive_, lit_, incomingLit_, {} };
    state.segments.reserve(segments_.size());
    for (const Segment &segment : segments_)
        state.segments.push_back(segment.lit);
    return state;
}

void GraphRow::beginTransition()
{
    if (suppress_ || pending_)
        return;
    // A change during a running transition finishes it first (rule 1.3.2).
    from_ = currentLighting();
    hasFrom_ = true;
    pending_ = true;
    // The row keeps showing the old lighting until the transition's owner times it: drawing
    // the new state now and the old one again when the (queued) transition starts flickers.
    litBlend_ = 0;
    const int generation = generation_;
    QMetaObject::invokeMethod(this, [this, generation] {
        pending_ = false;
        if (generation != generation_ || !hasFrom_)
            return;
        // Nobody animates it: show the new lighting at once.
        if (!isSignalConnected(QMetaMethod::fromSignal(&GraphRow::lightingTransition))) {
            litBlend_ = 1;
            emit changed();
            return;
        }
        emit lightingTransition();
    }, Qt::QueuedConnection);
}

void GraphRow::setLightingActive(bool value)
{
    if (lightingActive_ == value)
        return;
    beginTransition();
    lightingActive_ = value;
    emit changed();
}

void GraphRow::setLit(bool value)
{
    if (lit_ == value)
        return;
    beginTransition();
    lit_ = value;
    emit changed();
}

void GraphRow::setIncomingLit(bool value)
{
    if (incomingLit_ == value)
        return;
    beginTransition();
    incomingLit_ = value;
    emit changed();
}

void GraphRow::setRowKey(const QString &key)
{
    if (rowKey_ == key)
        return;
    rowKey_ = key;
    // A recycled row shows another commit: it starts at rest, and the changes the new
    // commit's values make during this turn are not transitions.
    ++generation_;
    hasFrom_ = false;
    litBlend_ = 1;
    suppress_ = true;
    QMetaObject::invokeMethod(this, [this] { suppress_ = false; }, Qt::QueuedConnection);
    emit changed();
}

qreal GraphRow::blend(bool from, bool to) const
{
    const qreal target = to ? 1 : 0;
    if (!hasFrom_ || litBlend_ >= 1)
        return target;
    const qreal start = from ? 1 : 0;
    return start + (target - start) * std::clamp(litBlend_, qreal(0), qreal(1));
}

qreal GraphRow::rowLitness() const
{
    return blend(!from_.active || from_.lit, !lightingActive_ || lit_);
}

void GraphRow::segmentLitness(const Lighting &state, std::size_t index, bool &upper, bool &lower) const
{
    const Segment &segment = segments_[index];
    const int explicitLit = index < state.segments.size() ? state.segments[index] : -1;
    const bool row = !state.active || state.lit;
    const bool arriving = !state.active || state.incoming;
    if (explicitLit >= 0) {
        upper = lower = !state.active || explicitLit == 1;
    } else if (segment.top && !segment.center) {
        upper = arriving;
        lower = row;
    } else {
        upper = lower = segment.top ? arriving : row;
    }
}

void GraphRow::setRow(const QVariant &row)
{
    const QVariantMap map = row.toMap();
    // The same commit's lane lighting may change with a new projection.
    {
        const QVariantList segments = map.value(QStringLiteral("segments")).toList();
        bool differs = segments.size() != qsizetype(segments_.size());
        for (qsizetype index = 0; !differs && index < segments.size(); ++index) {
            const QVariantList fields = segments[index].toList();
            differs = fields.size() < 6 || fields[5].toInt() != segments_[std::size_t(index)].lit;
        }
        if (differs && !segments_.empty())
            beginTransition();
    }
    rowValue_ = row;
    lane_ = map.value(QStringLiteral("lane")).toInt();
    shape_ = map.value(QStringLiteral("shape")).toInt();
    current_ = map.value(QStringLiteral("current")).toBool();
    wipStaged_ = map.value(QStringLiteral("wipStaged")).toInt();
    wipChanged_ = map.value(QStringLiteral("wipChanged")).toInt();
    segments_.clear();
    const QVariantList segments = map.value(QStringLiteral("segments")).toList();
    segments_.reserve(segments.size());
    for (const QVariant &value : segments) {
        const QVariantList fields = value.toList();
        if (fields.size() < 6)
            continue;
        segments_.push_back(Segment {
            fields[0].toInt(), fields[1].toInt(), fields[2].toInt(),
            fields[3].toBool(), fields[4].toBool(), fields[5].toInt(),
        });
    }
    emit changed();
}

void GraphRow::setClipRight(qreal value)
{
    if (qFuzzyCompare(clipRight_, value))
        return;
    clipRight_ = value;
    emit changed();
}

void GraphRow::setLaneColors(const QVariantList &colors)
{
    laneColorValues_ = colors;
    laneColors_.clear();
    for (const QVariant &color : colors)
        laneColors_.push_back(color.value<QColor>());
    emit changed();
}

QColor GraphRow::laneColor(int lane) const
{
    if (laneColors_.empty())
        return faintColor_;
    const int count = int(laneColors_.size());
    return laneColors_[std::size_t(((lane % count) + count) % count)];
}

void GraphRow::paint(QPainter *painter)
{
    if (drawProgress_ <= 0)
        return;
    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->save();
    // Lanes draw in from the top (NH-2, NH-7): nodes included.
    painter->setClipRect(QRectF(0, 0, clipRight_ > 0 ? clipRight_ : width(), height() * drawProgress_));
    paintSegments(painter);
    paintNodeBackground(painter);
    paintNode(painter);
    painter->restore();
}

void GraphRow::paintSegments(QPainter *painter)
{
    const Lighting now = currentLighting();
    const qreal centerY = height() / 2;
    // The graph is clipped at the metadata columns; lanes beyond it are skipped.
    const qreal visibleRight = (clipRight_ > 0 ? clipRight_ : width()) + laneWidth;
    auto pen = [&](int lane, qreal litness) {
        const QColor color = onAccent_ ? strongInk_
            : withAlpha(laneColor(lane), unlitOpacity + (1 - unlitOpacity) * litness);
        QPen result(color, graphRingStroke + (graphStrokeLit - graphRingStroke) * litness);
        result.setCapStyle(Qt::RoundCap);
        return result;
    };
    painter->setBrush(Qt::NoBrush);
    // Straight lanes first, then the edges that cross them.
    for (int pass = 0; pass < 2; ++pass) {
        for (std::size_t index = 0; index < segments_.size(); ++index) {
            const Segment &segment = segments_[index];
            if ((segment.from == segment.to) != (pass == 0))
                continue;
            const qreal fromX = laneX(segment.from);
            const qreal toX = laneX(segment.to);
            if (std::min(fromX, toX) > visibleRight)
                continue;
            const qreal startY = segment.top ? 0 : centerY;
            const qreal endY = segment.center ? centerY : height();
            QPainterPath path(QPointF(fromX, startY));
            if (fromX == toX) {
                path.lineTo(toX, endY);
            } else {
                const qreal midpoint = (startY + endY) / 2;
                path.cubicTo(fromX, midpoint, toX, midpoint, toX, endY);
            }
            bool upperNow = true, lowerNow = true, upperBefore = true, lowerBefore = true;
            segmentLitness(now, index, upperNow, lowerNow);
            if (hasFrom_)
                segmentLitness(from_, index, upperBefore, lowerBefore);
            const qreal upper = blend(upperBefore, upperNow);
            const qreal lower = blend(lowerBefore, lowerNow);
            if (!qFuzzyCompare(upper + 1, lower + 1)) {
                // The lane arriving from above and the row's own lighting differ.
                painter->save();
                painter->setClipRect(QRectF(0, 0, width(), centerY), Qt::IntersectClip);
                painter->setPen(pen(segment.from, upper));
                painter->drawPath(path);
                painter->restore();
                painter->save();
                painter->setClipRect(QRectF(0, centerY, width(), height() - centerY), Qt::IntersectClip);
                painter->setPen(pen(segment.from, lower));
                painter->drawPath(path);
                painter->restore();
            } else {
                painter->setPen(pen(segment.from, upper));
                painter->drawPath(path);
            }
            if (segment.kind == Missing) {
                const QPointF terminal(toX, endY == height() ? height() - 2 : endY);
                painter->setPen(Qt::NoPen);
                painter->setBrush(nodeBackground_);
                painter->drawEllipse(terminal, 2, 2);
                painter->setBrush(Qt::NoBrush);
                painter->setPen(QPen(onAccent_ ? strongInk_ : faintColor_, 1));
                painter->drawEllipse(terminal, 2, 2);
            }
        }
    }
}

void GraphRow::paintNodeBackground(QPainter *painter)
{
    const QPointF center(laneX(lane_), height() / 2);
    painter->setPen(Qt::NoPen);
    painter->setBrush(nodeBackground_);
    if (shape_ == Commit && current_) {
        painter->drawEllipse(center, graphHeadOuterRadius, graphHeadOuterRadius);
    } else if (shape_ == Boundary) {
        painter->drawRect(QRectF(center.x() - graphBoundarySquare / 2, center.y() - graphBoundarySquare / 2,
                                 graphBoundarySquare, graphBoundarySquare));
    } else if (shape_ == Graft || shape_ == Replace) {
        painter->drawEllipse(center, graphHeadOuterRadius, graphHeadOuterRadius);
    } else {
        painter->drawEllipse(center, graphCommitRadius, graphCommitRadius);
    }
}

void GraphRow::paintNode(QPainter *painter)
{
    const qreal litness = rowLitness();
    const qreal nodeAlpha = unlitOpacity + (1 - unlitOpacity) * litness;
    const qreal centerY = height() / 2;
    const qreal nodeX = laneX(lane_);
    const QPointF center(nodeX, centerY);
    const QColor nodeColor = onAccent_ ? strongInk_ : withAlpha(laneColor(lane_), nodeAlpha);
    auto ring = [&](qreal radius, const QColor &color, qreal stroke) {
        painter->setPen(QPen(color, stroke));
        painter->setBrush(Qt::NoBrush);
        painter->drawEllipse(center, radius, radius);
    };
    auto dot = [&](qreal radius, const QColor &color) {
        painter->setPen(Qt::NoPen);
        painter->setBrush(color);
        painter->drawEllipse(center, radius, radius);
    };
    switch (shape_) {
    case Wip:
    case WipConflict: {
        if (shape_ == Wip && wipStaged_ > 0 && wipStaged_ < wipChanged_) {
            painter->save();
            painter->setClipRect(QRectF(nodeX - graphCommitRadius, centerY, graphCommitRadius * 2, graphCommitRadius),
                                 Qt::IntersectClip);
            dot(graphCommitRadius, onAccent_ ? strongInk_ : addedColor_);
            painter->restore();
        }
        const QColor color = onAccent_ ? strongInk_ : shape_ == WipConflict ? conflictColor_ : wipColor_;
        drawDashedCircle(painter, center, graphCommitRadius, withAlpha(color, nodeAlpha));
        break;
    }
    case Commit:
        if (current_) {
            if (landing_) {
                paintLanding(painter, center, nodeColor);
            } else {
                ring(graphHeadOuterRadius, nodeColor, graphHeadOuterStroke);
                dot(graphHeadInnerRadius, nodeColor);
            }
        } else {
            ring(graphCommitRadius, nodeColor, graphRingStroke);
        }
        break;
    case Stash:
        drawDashedCircle(painter, center, graphCommitRadius, nodeColor);
        break;
    case Merge:
        ring(graphCommitRadius, nodeColor, graphRingStroke);
        dot(graphMergeDotRadius, nodeColor);
        break;
    case Boundary:
        painter->setPen(QPen(onAccent_ ? strongInk_ : wipColor_, graphBoundaryStroke));
        painter->setBrush(Qt::NoBrush);
        painter->drawRect(QRectF(center.x() - graphBoundarySquare / 2, center.y() - graphBoundarySquare / 2,
                                 graphBoundarySquare, graphBoundarySquare));
        break;
    case Graft:
    case Replace:
        ring(graphCommitRadius, nodeColor, graphBoundaryStroke);
        if (shape_ == Graft) {
            ring(graphHeadOuterRadius, nodeColor, graphBoundaryStroke);
        } else {
            painter->setPen(QPen(nodeColor, graphBoundaryStroke));
            const QRectF bounds(center.x() - graphHeadOuterRadius, center.y() - graphHeadOuterRadius,
                                graphHeadOuterRadius * 2, graphHeadOuterRadius * 2);
            // From -45° clockwise over 90°.
            painter->drawArc(bounds, 45 * 16, -90 * 16);
        }
        break;
    default:
        ring(graphCommitRadius, nodeColor, graphRingStroke);
    }
}

void GraphRow::paintLanding(QPainter *painter, QPointF center, const QColor &color)
{
    if (ringOpacity_ > 0)
        drawDashedCircle(painter, center, graphCommitRadius, withAlpha(color, ringOpacity_), 1 - ringClose_,
                         graphHeadOuterStroke);
    if (halo_ > 0) {
        const qreal radius = graphHeadInnerRadius + (graphHeadOuterRadius - graphHeadInnerRadius) * halo_;
        painter->setPen(QPen(color, graphHeadOuterStroke));
        painter->setBrush(Qt::NoBrush);
        painter->drawEllipse(center, radius, radius);
    }
    if (core_ > 0) {
        painter->setPen(Qt::NoPen);
        painter->setBrush(color);
        painter->drawEllipse(center, graphHeadInnerRadius * core_, graphHeadInnerRadius * core_);
    }
}

} // namespace gitlama

extern "C" void gitlama_register_native_types()
{
    qmlRegisterType<gitlama::GraphRow>("GitLamaNative", 1, 0, "GraphRow");
    qmlRegisterType<gitlama::TextFormatter>("GitLamaNative", 1, 0, "TextFormatter");
    qmlRegisterType<gitlama::SyntaxHighlighter>("GitLamaNative", 1, 0, "SyntaxHighlighter");
    qmlRegisterType<gitlama::LineColours>("GitLamaNative", 1, 0, "LineColours");
}

// The modifier keys held now (Qt::KeyboardModifiers): a command run from a
// menu or the palette reads Ctrl/Cmd to invert where inspection opens.
extern "C" int gitlama_keyboard_modifiers() {
    return static_cast<int>(QGuiApplication::queryKeyboardModifiers());
}

// Development screenshots: delivers a wheel event at window point (x, y)
// through Qt's own event delivery, as a mouse wheel (phase 0) or a touchpad
// gesture (phase 1 begin, 2 update, 3 end; pixel deltas). A negative phase
// moves the pointer there instead.
extern "C" bool gitlama_dev_wheel(double x, double y, int dx, int dy, int phase, int modifiers) {
    QWindow *window = QGuiApplication::focusWindow();
    if (!window) {
        const auto windows = QGuiApplication::topLevelWindows();
        for (QWindow *candidate : windows) {
            if (candidate->isVisible()) {
                window = candidate;
                break;
            }
        }
    }
    if (!window)
        return false;
    const QPointF local(x, y);
    if (phase < 0) {
        // A pointer move to (x, y) first, as a real pointer hovers before it scrolls.
        QMouseEvent move(QEvent::MouseMove, local, window->mapToGlobal(local), Qt::NoButton,
                         Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &move);
        return move.isAccepted();
    }
    const bool gesture = phase != 0;
    QWheelEvent event(local, window->mapToGlobal(local),
                      gesture ? QPoint(dx, dy) : QPoint(), QPoint(dx, dy),
                      Qt::NoButton, Qt::KeyboardModifiers(modifiers),
                      phase == 1 ? Qt::ScrollBegin : phase == 3 ? Qt::ScrollEnd
                          : gesture ? Qt::ScrollUpdate : Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(window, &event);
    return event.isAccepted();
}
