/**
 * Chat helper functions for shidashi
 *
 * Standalone functions for chat UI: markdown conversion, code copy buttons, toasts.
 */

import ClipboardJS from 'clipboard';

/**
 * Convert HTML content to approximate markdown
 */
export function htmlToMarkdown(el) {
  const clone = el.cloneNode(true);

  // Process code blocks first (pre > code)
  clone.querySelectorAll('pre').forEach(pre => {
    const code = pre.querySelector('code');
    const text = code ? code.textContent : pre.textContent;
    let lang = '';
    if (code) {
      const langClass = Array.from(code.classList).find(c => c.startsWith('language-') || c.startsWith('hljs-'));
      if (langClass) {
        lang = langClass.replace('language-', '').replace('hljs-', '');
      }
    }
    pre.textContent = '```' + lang + '\n' + text.trim() + '\n```';
  });

  // Inline code
  clone.querySelectorAll('code').forEach(code => {
    if (!code.closest('pre')) {
      code.textContent = '`' + code.textContent + '`';
    }
  });

  // Bold
  clone.querySelectorAll('strong, b').forEach(el => {
    el.textContent = '**' + el.textContent + '**';
  });

  // Italic
  clone.querySelectorAll('em, i').forEach(el => {
    el.textContent = '*' + el.textContent + '*';
  });

  // Links
  clone.querySelectorAll('a').forEach(a => {
    const href = a.getAttribute('href') || '';
    const text = a.textContent;
    a.textContent = `[${text}](${href})`;
  });

  // Lists
  clone.querySelectorAll('ul > li').forEach(li => {
    li.textContent = '- ' + li.textContent;
  });
  clone.querySelectorAll('ol > li').forEach((li, i) => {
    li.textContent = `${i + 1}. ` + li.textContent;
  });

  let text = clone.textContent || '';
  text = text.replace(/\n{3,}/g, '\n\n');
  return text.trim();
}

/**
 * Get conversation as markdown from a chat container
 */
export function getConversationMarkdown(chatId) {
  const chatContainer = document.getElementById(chatId);
  if (!chatContainer) {
    throw new Error(`Chat container not found: ${chatId}`);
  }

  const messages = chatContainer.querySelectorAll('shiny-chat-message');
  if (!messages.length) {
    throw new Error(`No messages found in chat container: ${chatId}`);
  }

  let markdown = '';
  messages.forEach((msg) => {
    const role = msg.getAttribute('data-role') === 'user' ? 'User' : 'Assistant';

    // Prefer the content attribute — it's the raw markdown from the server
    let text = msg.getAttribute('content') || '';

    // If content attribute is empty, try extracting from rendered DOM
    if (!text) {
      const stream = msg.querySelector('shiny-markdown-stream');
      if (stream) {
        text = htmlToMarkdown(stream);
      }
    }

    if (!text) return;

    markdown += `**${role}:**\n\n${text}\n\n---\n\n`;
  });

  return markdown.trim();
}

/**
 * Inject copy buttons into code blocks within a container
 */
export function injectCodeCopyButtons(container) {
  const preBlocks = container.querySelectorAll('pre');
  preBlocks.forEach(pre => {
    if (pre.querySelector('.shidashi-code-copy')) return;

    pre.style.position = 'relative';

    const copyBtn = document.createElement('button');
    copyBtn.type = 'button';
    copyBtn.className = 'shidashi-code-copy';
    copyBtn.title = 'Copy code';
    copyBtn.setAttribute('aria-label', 'Copy code');
    copyBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16">
      <path d="M4 1.5H3a2 2 0 0 0-2 2V14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V3.5a2 2 0 0 0-2-2h-1v1h1a1 1 0 0 1 1 1V14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3.5a1 1 0 0 1 1-1h1z"/>
      <path d="M9.5 1a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5h-3a.5.5 0 0 1-.5-.5v-1a.5.5 0 0 1 .5-.5zm-3-1A1.5 1.5 0 0 0 5 1.5v1A1.5 1.5 0 0 0 6.5 4h3A1.5 1.5 0 0 0 11 2.5v-1A1.5 1.5 0 0 0 9.5 0z"/>
    </svg>`;

    const clipboard = new ClipboardJS(copyBtn, {
      text: () => {
        const code = pre.querySelector('code');
        return code ? code.textContent : pre.textContent;
      }
    });

    clipboard.on('success', (e) => {
      e.clearSelection();
      copyBtn.classList.add('copied');
      copyBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16">
        <path d="M13.854 3.646a.5.5 0 0 1 0 .708l-7 7a.5.5 0 0 1-.708 0l-3.5-3.5a.5.5 0 1 1 .708-.708L6.5 10.293l6.646-6.647a.5.5 0 0 1 .708 0"/>
      </svg>`;
      setTimeout(() => {
        copyBtn.classList.remove('copied');
        copyBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16">
          <path d="M4 1.5H3a2 2 0 0 0-2 2V14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V3.5a2 2 0 0 0-2-2h-1v1h1a1 1 0 0 1 1 1V14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3.5a1 1 0 0 1 1-1h1z"/>
          <path d="M9.5 1a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5h-3a.5.5 0 0 1-.5-.5v-1a.5.5 0 0 1 .5-.5zm-3-1A1.5 1.5 0 0 0 5 1.5v1A1.5 1.5 0 0 0 6.5 4h3A1.5 1.5 0 0 0 11 2.5v-1A1.5 1.5 0 0 0 9.5 0z"/>
        </svg>`;
      }, 2000);
    });

    clipboard.on('error', (e) => {
      console.error('Code copy error:', e.action, e.trigger);
    });

    pre.appendChild(copyBtn);
  });
}

/**
 * Show a brief toast notification
 */
export function showToast(message) {
  let container = document.querySelector('.shidashi-toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'shidashi-toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = 'shidashi-toast';
  toast.textContent = message;
  container.appendChild(toast);

  requestAnimationFrame(() => {
    toast.classList.add('show');
    setTimeout(() => {
      toast.classList.remove('show');
      setTimeout(() => toast.remove(), 300);
    }, 2000);
  });
}
