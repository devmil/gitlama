// Fixed line heights and background bands for a Qt Quick TextEdit's
// document: the conflict resolver's result editor keeps every line as tall
// as a comparison row, so unchanged text stays level across the panes.
#pragma once

#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>

namespace gitlama {

class TextFormatter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    Q_PROPERTY(qreal lineHeight READ lineHeight WRITE setLineHeight NOTIFY lineHeightChanged)

public:
    explicit TextFormatter(QObject *parent = nullptr);

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *document);
    qreal lineHeight() const { return m_lineHeight; }
    void setLineHeight(qreal height);

signals:
    void documentChanged();
    void lineHeightChanged();

private:
    void apply(int from, int added);

    QPointer<QQuickTextDocument> m_document;
    QMetaObject::Connection m_contents;
    qreal m_lineHeight = 0;
    bool m_applying = false;
};

} // namespace gitlama
