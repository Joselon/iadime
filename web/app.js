const state = {
  sessionId: crypto.randomUUID(),
  history: [],
  models: [],
  provider: 'openai',
};

const messagesEl = document.getElementById('messages');
const promptEl = document.getElementById('prompt');
const composerEl = document.getElementById('composer');
const composerButtonEl = composerEl.querySelector('button');
const sidebarToggleEl = document.getElementById('sidebarToggle');
const scrollBottomBtnEl = document.getElementById('scrollBottomBtn');
const floatingControlsEl = document.querySelector('.floating-controls');
const appShellEl = document.querySelector('.app-shell');
const sidebarEl = document.getElementById('sidebar');
const modelSelectEl = document.getElementById('modelSelect');
const providerSelectEl = document.getElementById('providerSelect');
const clearBtnEl = document.getElementById('clearBtn');
const exportBtnEl = document.getElementById('exportBtn');
const importBtnEl = document.getElementById('importBtn');
const conversationNameEl = document.getElementById('conversationName');
const conversationListEl = document.getElementById('conversationList');
let typingIndicatorEl = null;
let currentSpeech = null;
let currentVoiceButton = null;
let sidebarOpen = window.innerWidth > 800;

function syncSidebarState() {
  const isMobile = window.innerWidth <= 800;
  appShellEl.classList.toggle('sidebar-collapsed', !sidebarOpen);
  sidebarEl.classList.toggle('is-open', sidebarOpen && isMobile);
  sidebarToggleEl.setAttribute('aria-expanded', String(sidebarOpen));
  sidebarToggleEl.textContent = sidebarOpen ? '×' : '☰';
  syncFloatingControls();
}

function getFloatingControlsRight() {
  const isMobile = window.innerWidth <= 800;
  if (!sidebarOpen || isMobile || !sidebarEl) {
    return '1rem';
  }
  const sidebarRect = sidebarEl.getBoundingClientRect();
  const rightDistance = window.innerWidth - sidebarRect.left + 12;
  return `${rightDistance}px`;
}

function syncFloatingControls() {
  if (!floatingControlsEl) return;
  floatingControlsEl.style.right = getFloatingControlsRight();
}

function isScrolledToBottom() {
  return messagesEl.scrollHeight - messagesEl.scrollTop <= messagesEl.clientHeight + 4;
}

function updateScrollButtonState() {
  scrollBottomBtnEl.textContent = '⇩';
  scrollBottomBtnEl.classList.remove('hidden');
  scrollBottomBtnEl.setAttribute('aria-label', 'Ir al final de la conversación');
}

function toggleSidebar(force) {
  sidebarOpen = typeof force === 'boolean' ? force : !sidebarOpen;
  syncSidebarState();
}

function renderMermaidBlocks(container) {
  if (!window.mermaid || typeof window.mermaid.run !== 'function') {
    return;
  }
  const nodes = Array.from(container.querySelectorAll('.mermaid'));
  if (!nodes.length) {
    return;
  }
  nodes.forEach((node) => {
    node.removeAttribute('data-processed');
  });
  window.mermaid.initialize({
    startOnLoad: false,
    theme: 'dark',
    securityLevel: 'loose',
  });
  window.mermaid.run({ nodes });
}

function renderMarkdown(content) {
  const container = document.createElement('div');
  container.className = 'message-body';
  const source = String(content || '');

  if (window.markdownit) {
    const md = window.markdownit({
      html: false,
      linkify: true,
      typographer: true,
      breaks: true,
    });

    md.renderer.rules.fence = (tokens, idx) => {
      const token = tokens[idx];
      const info = token.info ? token.info.trim() : '';
      const lang = info.split(/\s+/)[0] || '';
      const code = token.content;
      if (lang === 'mermaid') {
        return `
          <div class="mermaid-wrapper" data-mermaid-source="${escapeHtml(code)}">
            <div class="mermaid">${code}</div>
          </div>
        `;
      }
      const highlighted = window.hljs && window.hljs.getLanguage(lang)
        ? window.hljs.highlight(code, { language: lang }).value
        : window.hljs
          ? window.hljs.highlightAuto(code).value
          : escapeHtml(code);
      return `<pre class="code-block"><code class="language-${lang || 'text'}">${highlighted}</code></pre>`;
    };

    if (window.markdownitHighlightjs && window.hljs) {
      md.use(window.markdownitHighlightjs, { inline: false });
    }

    container.innerHTML = md.render(source);
  } else {
    container.textContent = source;
  }

  renderMermaidBlocks(container);
  return container;
}

function copyTextToClipboard(text) {
  if (!text) return;
  if (navigator.clipboard && navigator.clipboard.writeText) {
    return navigator.clipboard.writeText(text);
  }
  return new Promise((resolve, reject) => {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);
    const success = document.execCommand('copy');
    document.body.removeChild(textarea);
    success ? resolve() : reject(new Error('Copy failed'));
  });
}

function attachInlineMessageControls(container, rawContent) {
  if (!container) return;

  const codeBlocks = Array.from(container.querySelectorAll('pre.code-block'));
  codeBlocks.forEach((block) => {
    block.style.position = 'relative';
    const codeElement = block.querySelector('code');
    if (!codeElement) return;
    const copyCodeBtn = document.createElement('button');
    copyCodeBtn.type = 'button';
    copyCodeBtn.className = 'inline-action-button';
    copyCodeBtn.textContent = '📋';
    copyCodeBtn.title = 'Copiar bloque de código';
    copyCodeBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      copyTextToClipboard(codeElement.textContent || '').then(() => {
        copyCodeBtn.textContent = '✅';
        setTimeout(() => { copyCodeBtn.textContent = '📋'; }, 900);
      });
    });
    block.appendChild(copyCodeBtn);
  });

  const mermaidWrappers = Array.from(container.querySelectorAll('.mermaid-wrapper'));
  mermaidWrappers.forEach((wrapper) => {
    wrapper.style.position = 'relative';
    const copyMermaidBtn = document.createElement('button');
    copyMermaidBtn.type = 'button';
    copyMermaidBtn.className = 'inline-action-button';
    copyMermaidBtn.textContent = '📋';
    copyMermaidBtn.title = 'Copiar definición Mermaid';
    copyMermaidBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      const source = wrapper.dataset.mermaidSource || '';
      if (!source.trim()) return;
      copyTextToClipboard(source).then(() => {
        copyMermaidBtn.textContent = '✅';
        setTimeout(() => { copyMermaidBtn.textContent = '📋'; }, 900);
      });
    });
    wrapper.appendChild(copyMermaidBtn);
  });
}

function setComposerBusy(isBusy) {
  composerEl.classList.toggle('is-waiting', isBusy);
  promptEl.disabled = isBusy;
  composerButtonEl.disabled = isBusy;
  composerButtonEl.textContent = isBusy ? 'Pensando…' : 'Enviar';
}

function showTypingIndicator() {
  hideTypingIndicator();
  const bubble = document.createElement('div');
  bubble.className = 'message assistant typing';
  bubble.innerHTML = '<div class="typing-indicator" aria-label="Esperando respuesta"><span></span><span></span><span></span></div>';
  messagesEl.appendChild(bubble);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  typingIndicatorEl = bubble;
}

function hideTypingIndicator() {
  if (typingIndicatorEl) {
    typingIndicatorEl.remove();
    typingIndicatorEl = null;
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function normalizeSpeechText(content) {
  return String(content)
    .replace(/\[(.*?)\]\((.*?)\)/g, '$1')
    .replace(/(`{1,3})(.*?)\1/g, '$2')
    .replace(/\*\*(.*?)\*\*/g, '$1')
    .replace(/\*(.*?)\*/g, '$1')
    .replace(/__([^_]+)__/g, '$1')
    .replace(/_(.*?)_/g, '$1')
    .replace(/^>\s?/gm, '')
    .replace(/^[#*\-\+\s]+/gm, '')
    .replace(/\n{2,}/g, '\n')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

function stopSpeech() {
  if (currentSpeech) {
    window.speechSynthesis.cancel();
    currentSpeech = null;
  }
  if (currentVoiceButton) {
    currentVoiceButton.textContent = '🔊';
    currentVoiceButton.title = 'Leer mensaje en voz alta';
    currentVoiceButton = null;
  }
}

function speakMessage(content, button) {
  if (currentSpeech && currentVoiceButton === button) {
    stopSpeech();
    return;
  }

  stopSpeech();

  const messageText = normalizeSpeechText(content);
  const utterance = new SpeechSynthesisUtterance(messageText);
  utterance.lang = document.documentElement.lang || 'es-ES';

  utterance.addEventListener('end', () => {
    if (currentVoiceButton === button) {
      stopSpeech();
    }
  });
  utterance.addEventListener('error', () => {
    stopSpeech();
  });

  currentSpeech = utterance;
  currentVoiceButton = button;
  button.textContent = '⏹️';
  button.title = 'Detener lectura';
  window.speechSynthesis.speak(utterance);
}

function addMessage(role, content, options = { renderMarkdown: true }) {
  const bubble = document.createElement('div');
  bubble.className = `message ${role}`;
  bubble.style.position = 'relative';
  bubble.dataset.rawContent = content;

  const actions = document.createElement('div');
  actions.className = 'message-actions';

  const copyBtn = document.createElement('button');
  copyBtn.type = 'button';
  copyBtn.className = 'message-action-button';
  copyBtn.textContent = '📋';
  copyBtn.title = 'Copiar mensaje completo';
  copyBtn.setAttribute('aria-label', 'Copiar mensaje completo');
  copyBtn.addEventListener('click', (event) => {
    event.stopPropagation();
    copyTextToClipboard(content).then(() => {
      copyBtn.textContent = '✅';
      setTimeout(() => { copyBtn.textContent = '📋'; }, 900);
    });
  });

  const speakBtn = document.createElement('button');
  speakBtn.type = 'button';
  speakBtn.className = 'message-action-button voice-button';
  speakBtn.textContent = '🔊';
  speakBtn.title = 'Leer mensaje en voz alta';
  speakBtn.setAttribute('aria-label', 'Leer mensaje en voz alta');
  speakBtn.addEventListener('click', (event) => {
    event.stopPropagation();
    speakMessage(content, speakBtn);
  });

  actions.appendChild(copyBtn);
  actions.appendChild(speakBtn);
  bubble.appendChild(actions);

  if (role === 'assistant' && options.renderMarkdown) {
    const rendered = renderMarkdown(content);
    bubble.appendChild(rendered);
    attachInlineMessageControls(rendered, content);
  } else {
    const body = document.createElement('div');
    body.className = 'message-body';
    body.textContent = content;
    bubble.appendChild(body);
  }

  messagesEl.appendChild(bubble);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  updateScrollButtonState();
}

async function loadModels() {
  const response = await fetch(`/models?provider=${encodeURIComponent(state.provider)}`);
  const payload = await response.json();
  state.models = payload.models || [];
  state.provider = payload.provider || state.provider;
  providerSelectEl.value = state.provider;
  modelSelectEl.innerHTML = '';
  state.models.forEach((model) => {
    const option = document.createElement('option');
    option.value = model;
    option.textContent = model;
    modelSelectEl.appendChild(option);
  });
}

async function refreshConversations() {
  const response = await fetch('/conversations');
  const payload = await response.json();
  const conversations = payload.conversations || [];
  conversationListEl.innerHTML = '';
  if (!conversations.length) {
    const empty = document.createElement('li');
    empty.className = 'conversation-empty';
    empty.textContent = 'No hay conversaciones guardadas';
    conversationListEl.appendChild(empty);
    return conversations;
  }
  conversations.forEach((name) => {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = name;
    button.addEventListener('click', async () => {
      conversationNameEl.value = name;
      const response = await fetch('/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: state.sessionId, name }),
      });
      const payload = await response.json();
      if (payload.history) {
        state.history = payload.history;
        await refreshHistory();
        addMessage('assistant', payload.message || 'Conversación cargada');
      } else {
        addMessage('assistant', payload.error || 'No se pudo cargar');
      }
    });
    item.appendChild(button);
    conversationListEl.appendChild(item);
  });
  return conversations;
}

async function refreshHistory() {
  const response = await fetch(`/history?session_id=${state.sessionId}`);
  const payload = await response.json();
  messagesEl.innerHTML = '';
  (payload.history || []).forEach((entry) => {
    addMessage(entry.role === 'assistant' ? 'assistant' : 'user', entry.content);
  });
  requestAnimationFrame(updateScrollButtonState);
  return payload.history || [];
}

sidebarToggleEl.addEventListener('click', () => toggleSidebar());
scrollBottomBtnEl.addEventListener('click', () => {
  messagesEl.scrollTop = messagesEl.scrollHeight;
  promptEl.focus();
  requestAnimationFrame(updateScrollButtonState);
});
messagesEl.addEventListener('scroll', updateScrollButtonState, { passive: true });
window.addEventListener('resize', () => {
  syncSidebarState();
  requestAnimationFrame(updateScrollButtonState);
});

composerEl.addEventListener('submit', async (event) => {
  event.preventDefault();
  const prompt = promptEl.value.trim();
  if (!prompt || composerButtonEl.disabled) return;

  addMessage('user', prompt);
  promptEl.value = '';
  promptEl.style.height = '';
  showTypingIndicator();
  setComposerBusy(true);

  try {
    const response = await fetch('/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        prompt,
        session_id: state.sessionId,
        model: modelSelectEl.value,
        provider: state.provider,
        history: state.history,
      }),
    });
    const payload = await response.json();
    if (payload.answer) {
      addMessage('assistant', payload.answer);
      if (!payload.command) {
        state.history.push({ role: 'user', content: prompt });
        state.history.push({ role: 'assistant', content: payload.answer });
      }
    } else {
      addMessage('assistant', payload.error || 'No se pudo responder');
    }
  } catch (error) {
    addMessage('assistant', 'No se pudo completar la solicitud.');
  } finally {
    hideTypingIndicator();
    setComposerBusy(false);
  }
});

providerSelectEl.addEventListener('change', async () => {
  state.provider = providerSelectEl.value;
  document.body.dataset.provider = state.provider;
  await loadModels();
});

clearBtnEl.addEventListener('click', () => {
  state.history = [];
  messagesEl.innerHTML = '';
});

exportBtnEl.addEventListener('click', async () => {
  const name = (conversationNameEl.value || 'conversacion').trim();
  const response = await fetch('/export', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: state.sessionId, name, history: state.history }),
  });
  const payload = await response.json();
  if (payload.conversations) {
    await refreshConversations();
  }
  addMessage('assistant', payload.message || 'Conversación guardada');
});

importBtnEl.addEventListener('click', async () => {
  const name = (conversationNameEl.value || 'conversacion').trim();
  const response = await fetch('/import', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: state.sessionId, name }),
  });
  const payload = await response.json();
  if (payload.history) {
    state.history = payload.history;
    await refreshHistory();
    await refreshConversations();
    addMessage('assistant', payload.message || 'Conversación cargada');
  } else {
    addMessage('assistant', payload.error || 'No se pudo cargar');
  }
});

(async () => {
  syncSidebarState();
  requestAnimationFrame(updateScrollButtonState);
  await loadModels();
  await refreshHistory();
  await refreshConversations();
  addMessage('assistant', 'Hola. Estoy listo para ayudarte desde la web.');
})();
