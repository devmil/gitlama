#pragma once

// One row of the history graph: the
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
    Q_PROPERTY(bool lightingActive READ lightingActive WRITE setLightingActive NOTIFY changed FINAL)
    Q_PROPERTY(bool lit READ lit WRITE setLit NOTIFY changed FINAL)
    Q_PROPERTY(bool incomingLit READ incomingLit WRITE setIncomingLit NOTIFY changed FINAL)
    /// The commit the row shows; a new key (a recycled row) starts without a transition.
    Q_PROPERTY(QString rowKey READ rowKey WRITE setRowKey NOTIFY changed FINAL)
    /// The lighting transition (NH-3): 0 shows the lighting before the last change, 1 the
    /// current one. A change emits `lightingTransition`; the view animates this to 1.
    Q_PROPERTY(qreal litBlend MEMBER litBlend_ NOTIFY changed FINAL)
    /// How lit the row's node is now, 0..1 (for the row's text).
    Q_PROPERTY(qreal rowLitness READ rowLitness NOTIFY changed FINAL)
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
    bool lightingActive() const { return lightingActive_; }
    void setLightingActive(bool value);
    bool lit() const { return lit_; }
    void setLit(bool value);
    bool incomingLit() const { return incomingLit_; }
    void setIncomingLit(bool value);
    QString rowKey() const { return rowKey_; }
    void setRowKey(const QString &key);
    qreal rowLitness() const;

    void paint(QPainter *painter) override;

    /// The x of lane `lane`'s centre.
    static qreal laneX(int lane);

signals:
    void changed();
    /// The row's lighting changed while it showed the same commit.
    void lightingTransition();

private:
    struct Segment {
        int from = 0;
        int to = 0;
        int kind = 0;
        bool top = false;
        bool center = false;
        int lit = -1;
    };

    /// The lighting a row is drawn with: before or after a change.
    struct Lighting {
        bool active = false;
        bool lit = false;
        bool incoming = false;
        std::vector<int> segments;
    };
    Lighting currentLighting() const;
    /// Records the lighting before a change, once per event-loop turn.
    void beginTransition();
    /// 0..1 litness of an element under `from` and the current lighting, blended.
    qreal blend(bool from, bool to) const;
    void segmentLitness(const Lighting &state, std::size_t index, bool &upper, bool &lower) const;

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
    QString rowKey_;
    qreal litBlend_ = 1;
    Lighting from_;
    bool hasFrom_ = false;
    bool pending_ = false;
    bool suppress_ = false;
    int generation_ = 0;
    qreal drawProgress_ = 1;
    bool landing_ = false;
    qreal ringOpacity_ = 0;
    qreal ringClose_ = 0;
    qreal halo_ = 0;
    qreal core_ = 0;
};

} // namespace gitlama
