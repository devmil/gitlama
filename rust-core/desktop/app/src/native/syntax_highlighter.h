// Syntax colours for a Qt Quick TextEdit's document: the conflict resolver's
// result editor. GitLama's Rust side parses the text (text_syntax_page) and
// hands each line's runs here; the runs ride on their text blocks, so lines
// an edit moves keep their colours until the new text is coloured.
#pragma once

#include <QColor>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <QVariant>

namespace gitlama {

class BlockHighlighter;

class SyntaxHighlighter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    /// Colour by category name ("keyword", "string", ...); missing categories stay plain.
    Q_PROPERTY(QVariantMap palette READ palette WRITE setPalette NOTIFY paletteChanged)

public:
    explicit SyntaxHighlighter(QObject *parent = nullptr);
    ~SyntaxHighlighter() override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *document);
    QVariantMap palette() const { return m_palette; }
    void setPalette(const QVariantMap &palette);

    /// Sets the runs of the lines from the one-based `firstLine`: each entry is a list of
    /// [start, end, category] over UTF-16 offsets of its line.
    Q_INVOKABLE void setLines(int firstLine, const QVariantList &lines);
    /// Drops every colour.
    Q_INVOKABLE void clear();

    QColor colour(const QString &category) const { return m_colours.value(category); }

signals:
    void documentChanged();
    void paletteChanged();

private:
    QPointer<QQuickTextDocument> m_document;
    QPointer<BlockHighlighter> m_highlighter;
    QVariantMap m_palette;
    QHash<QString, QColor> m_colours;
};

} // namespace gitlama
