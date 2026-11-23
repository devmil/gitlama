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
#include <QVector>

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

class LineHighlighter;

/// Colours a one-line TextEdit (a diff line) from runs of explicit colours: plain text with
/// formats instead of rich text, which a line would otherwise parse on every rebind.
class LineColours : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY documentChanged)
    /// [start, end, colour] triples over UTF-16 offsets of the line.
    Q_PROPERTY(QVariantList runs READ runs WRITE setRuns NOTIFY runsChanged)

public:
    explicit LineColours(QObject *parent = nullptr);
    ~LineColours() override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *document);
    QVariantList runs() const { return m_runs; }
    void setRuns(const QVariantList &runs);

    struct Run
    {
        int start;
        int end;
        QColor colour;
    };
    const QVector<Run> &parsed() const { return m_parsed; }

signals:
    void documentChanged();
    void runsChanged();

private:
    QPointer<QQuickTextDocument> m_document;
    QPointer<LineHighlighter> m_highlighter;
    QVariantList m_runs;
    QVector<Run> m_parsed;
};

} // namespace gitlama
