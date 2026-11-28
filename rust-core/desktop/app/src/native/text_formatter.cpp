#include "text_formatter.h"

#include <QTextBlock>
#include <QTextBlockFormat>
#include <QTextCursor>
#include <QTextDocument>

namespace gitlama {

TextFormatter::TextFormatter(QObject *parent)
    : QObject(parent)
{
}

void TextFormatter::setDocument(QQuickTextDocument *document)
{
    if (m_document == document)
        return;
    if (m_contents)
        QObject::disconnect(m_contents);
    m_document = document;
    if (document != nullptr && document->textDocument() != nullptr) {
        m_contents = connect(document->textDocument(), &QTextDocument::contentsChange, this,
                             [this](int from, int, int added) { apply(from, added); });
    }
    apply(0, -1);
    emit documentChanged();
}

void TextFormatter::setLineHeight(qreal height)
{
    if (qFuzzyCompare(m_lineHeight, height))
        return;
    m_lineHeight = height;
    apply(0, -1);
    emit lineHeightChanged();
}

// Sets the fixed line height on the blocks from `from` over `added`
// characters (every block when `added` is negative). Formatting changes
// the document again, which this ignores.
void TextFormatter::apply(int from, int added)
{
    if (m_applying || m_document == nullptr || m_lineHeight <= 0)
        return;
    QTextDocument *text = m_document->textDocument();
    if (text == nullptr)
        return;
    m_applying = true;
    QTextBlock block = added < 0 ? text->firstBlock() : text->findBlock(from);
    const QTextBlock last = added < 0 ? text->lastBlock() : text->findBlock(from + added);
    QTextCursor cursor(text);
    cursor.beginEditBlock();
    while (block.isValid()) {
        QTextBlockFormat format = block.blockFormat();
        if (format.lineHeightType() != QTextBlockFormat::FixedHeight || !qFuzzyCompare(format.lineHeight(), m_lineHeight)) {
            format.setLineHeight(m_lineHeight, QTextBlockFormat::FixedHeight);
            cursor.setPosition(block.position());
            cursor.setBlockFormat(format);
        }
        if (block == last)
            break;
        block = block.next();
    }
    cursor.endEditBlock();
    m_applying = false;
}

} // namespace gitlama
