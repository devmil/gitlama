#include "syntax_highlighter.h"

#include <QSyntaxHighlighter>
#include <QTextBlock>
#include <QTextBlockUserData>
#include <QTextDocument>
#include <QVector>

namespace gitlama {

namespace {

struct Run
{
    int start;
    int end;
    QString category;
};

class Runs : public QTextBlockUserData
{
public:
    QVector<Run> runs;
};

} // namespace

class BlockHighlighter : public QSyntaxHighlighter
{
public:
    BlockHighlighter(QTextDocument *document, SyntaxHighlighter *owner)
        : QSyntaxHighlighter(document)
        , m_owner(owner)
    {
    }

protected:
    void highlightBlock(const QString &text) override
    {
        const auto *data = static_cast<Runs *>(currentBlockUserData());
        if (data == nullptr)
            return;
        const int length = int(text.size());
        for (const Run &run : data->runs) {
            const QColor colour = m_owner->colour(run.category);
            if (!colour.isValid())
                continue;
            const int start = qBound(0, run.start, length);
            const int end = qBound(start, run.end, length);
            if (end > start)
                setFormat(start, end - start, colour);
        }
    }

private:
    SyntaxHighlighter *m_owner;
};

SyntaxHighlighter::SyntaxHighlighter(QObject *parent)
    : QObject(parent)
{
}

SyntaxHighlighter::~SyntaxHighlighter()
{
    delete m_highlighter;
}

void SyntaxHighlighter::setDocument(QQuickTextDocument *document)
{
    if (m_document == document)
        return;
    delete m_highlighter;
    m_document = document;
    if (document != nullptr && document->textDocument() != nullptr)
        m_highlighter = new BlockHighlighter(document->textDocument(), this);
    emit documentChanged();
}

void SyntaxHighlighter::setPalette(const QVariantMap &palette)
{
    if (m_palette == palette)
        return;
    m_palette = palette;
    m_colours.clear();
    for (auto it = palette.cbegin(); it != palette.cend(); ++it) {
        const QColor colour = it.value().value<QColor>();
        if (colour.isValid())
            m_colours.insert(it.key(), colour);
    }
    if (m_highlighter)
        m_highlighter->rehighlight();
    emit paletteChanged();
}

void SyntaxHighlighter::setLines(int firstLine, const QVariantList &lines)
{
    if (!m_highlighter || m_document == nullptr || m_document->textDocument() == nullptr || firstLine < 1)
        return;
    QTextDocument *text = m_document->textDocument();
    QTextBlock block = text->findBlockByNumber(firstLine - 1);
    for (const QVariant &line : lines) {
        if (!block.isValid())
            break;
        auto *data = new Runs;
        for (const QVariant &entry : line.toList()) {
            const QVariantList run = entry.toList();
            if (run.size() < 3)
                continue;
            data->runs.append({ run.at(0).toInt(), run.at(1).toInt(), run.at(2).toString() });
        }
        block.setUserData(data);
        m_highlighter->rehighlightBlock(block);
        block = block.next();
    }
}

void SyntaxHighlighter::clear()
{
    if (!m_highlighter || m_document == nullptr || m_document->textDocument() == nullptr)
        return;
    for (QTextBlock block = m_document->textDocument()->firstBlock(); block.isValid(); block = block.next())
        block.setUserData(nullptr);
    m_highlighter->rehighlight();
}

class LineHighlighter : public QSyntaxHighlighter
{
public:
    LineHighlighter(QTextDocument *document, LineColours *owner)
        : QSyntaxHighlighter(document)
        , m_owner(owner)
    {
    }

protected:
    void highlightBlock(const QString &text) override
    {
        // Offsets are of the whole line; a wrapped line is still one block.
        const int offset = currentBlock().position();
        const int length = int(text.size());
        for (const LineColours::Run &run : m_owner->parsed()) {
            const int start = qBound(0, run.start - offset, length);
            const int end = qBound(start, run.end - offset, length);
            if (end > start)
                setFormat(start, end - start, run.colour);
        }
    }

private:
    LineColours *m_owner;
};

LineColours::LineColours(QObject *parent)
    : QObject(parent)
{
}

LineColours::~LineColours()
{
    delete m_highlighter;
}

void LineColours::setDocument(QQuickTextDocument *document)
{
    if (m_document == document)
        return;
    delete m_highlighter;
    m_document = document;
    if (document != nullptr && document->textDocument() != nullptr)
        m_highlighter = new LineHighlighter(document->textDocument(), this);
    emit documentChanged();
}

void LineColours::setRuns(const QVariantList &runs)
{
    if (m_runs == runs)
        return;
    const bool hadRuns = !m_parsed.isEmpty();
    m_runs = runs;
    m_parsed.clear();
    m_parsed.reserve(runs.size());
    for (const QVariant &entry : runs) {
        const QVariantList run = entry.toList();
        if (run.size() < 3)
            continue;
        const QColor colour(run.at(2).toString());
        if (colour.isValid())
            m_parsed.append({ run.at(0).toInt(), run.at(1).toInt(), colour });
    }
    if (m_highlighter != nullptr && (hadRuns || !m_parsed.isEmpty()))
        m_highlighter->rehighlight();
    emit runsChanged();
}

} // namespace gitlama
