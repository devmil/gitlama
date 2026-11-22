#pragma once

// One row of the history graph (the Flutter _HistoryGraphPainter): the
// lanes passing through it, the edges joining them and the commit's node.
// Rust lays the graph out; this item only paints one row's geometry.

#include <QColor>
#include <QQuickPaintedItem>
#include <QVariant>
#include <vector>

namespace gitlama {

class GraphRow : public QQuickPaintedItem {
    Q_OBJECT
    /// {lane, shape, current, segments: [[from, to, kind, top, center, lit]],
    ///  wipStaged, wipChanged}; lit is -1 (follows the row), 0 or 1.
    Q_PROPERTY(QVariant row READ row WRITE setRow NOTIFY changed FINAL)
    Q_PROPERTY(qreal clipRight READ clipRight WRITE setClipRight NOTIFY changed FINAL)
    Q_PROPERTY(QVariantList laneColors READ laneColors WRITE setLaneColors NOTIFY changed FINAL)
    Q_PROPERTY(QColor wipColor MEMBER wipColor_ NOTIFY changed FINAL)
    Q_PROPERTY(QColor conflictColor MEMBER conflictColor_ NOTIFY changed FINAL)
    Q_PROPERTY(QColor nodeBackground MEMBER nodeBackground_ NOTIFY changed FINAL)
    Q_PROPERTY(QColor strongInk MEMBER strongInk_ NOTIFY changed FINAL)
    Q_PROPERTY(QColor faintColor MEMBER faintColor_ NOTIFY changed FINAL)
    Q_PROPERTY(QColor addedColor MEMBER addedColor_ NOTIFY changed FINAL)
    Q_PROPERTY(bool strong MEMBER onAccent_ NOTIFY changed FINAL)
    /// Lighting: whether any lane is lit, this row's node and the lane
    /// arriving from above.
    Q_PROPERTY(bool lightingActive MEMBER lightingActive_ NOTIFY changed FINAL)
    Q_PROPERTY(bool lit MEMBER lit_ NOTIFY changed FINAL)
    Q_PROPERTY(bool incomingLit MEMBER incomingLit_ NOTIFY changed FINAL)
    /// How far the lanes have drawn in from the top (0..1).
    Q_PROPERTY(qreal drawProgress MEMBER drawProgress_ NOTIFY changed FINAL)
    /// The commit landing: the WIP ring closing into the HEAD node.
    Q_PROPERTY(bool landing MEMBER landing_ NOTIFY changed FINAL)
    Q_PROPERTY(qreal ringOpacity MEMBER ringOpacity_ NOTIFY changed FINAL)
    Q_PROPERTY(qreal ringClose MEMBER ringClose_ NOTIFY changed FINAL)
    Q_PROPERTY(qreal halo MEMBER halo_ NOTIFY changed FINAL)
    Q_PROPERTY(qreal core MEMBER core_ NOTIFY changed FINAL)

public:
    explicit GraphRow(QQuickItem *parent = nullptr);

    QVariant row() const { return rowValue_; }
    void setRow(const QVariant &row);
    qreal clipRight() const { return clipRight_; }
    void setClipRight(qreal value);
    QVariantList laneColors() const { return laneColorValues_; }
    void setLaneColors(const QVariantList &colors);

    void paint(QPainter *painter) override;

    /// The x of lane `lane`'s centre.
    static qreal laneX(int lane);

signals:
    void changed();

private:
    struct Segment {
        int from = 0;
        int to = 0;
        int kind = 0;
        bool top = false;
        bool center = false;
        int lit = -1;
    };

    QColor laneColor(int lane) const;
    void paintSegments(QPainter *painter);
    void paintNodeBackground(QPainter *painter);
    void paintNode(QPainter *painter);
    void paintLanding(QPainter *painter, QPointF center, const QColor &color);

    QVariant rowValue_;
    int lane_ = 0;
    int shape_ = 0;
    bool current_ = false;
    int wipStaged_ = 0;
    int wipChanged_ = 0;
    std::vector<Segment> segments_;
    qreal clipRight_ = 0;
    QVariantList laneColorValues_;
    std::vector<QColor> laneColors_;
    QColor wipColor_;
    QColor conflictColor_;
    QColor nodeBackground_;
    QColor strongInk_;
    QColor faintColor_;
    QColor addedColor_;
    bool onAccent_ = false;
    bool lightingActive_ = false;
    bool lit_ = false;
    bool incomingLit_ = false;
    qreal drawProgress_ = 1;
    bool landing_ = false;
    qreal ringOpacity_ = 0;
    qreal ringClose_ = 0;
    qreal halo_ = 0;
    qreal core_ = 0;
};

} // namespace gitlama
