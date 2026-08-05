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
let sidebarOpen = window.innerWidth > 800;

function syncSidebarState() {
  const isMobile = window.innerWidth <= 800;
  appShellEl.classList.toggle('sidebar-collapsed', !sidebarOpen);
  sidebarEl.classList.toggle('is-open', sidebarOpen && isMobile);
  sidebarToggleEl.setAttribute('aria-expanded', String(sidebarOpen));
  sidebarToggleEl.textContent = sidebarOpen ? '×' : '☰';
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
        return `<div class="mermaid">${code}</div>`;
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

function addMessage(role, content) {
  const bubble = document.createElement('div');
  bubble.className = `message ${role}`;
  if (role === 'assistant') {
    const rendered = renderMarkdown(content);
    bubble.appendChild(rendered);
  } else {
    bubble.textContent = content;
  }
  messagesEl.appendChild(bubble);
  messagesEl.scrollTop = messagesEl.scrollHeight;
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
  return payload.history || [];
}

sidebarToggleEl.addEventListener('click', () => toggleSidebar());
window.addEventListener('resize', syncSidebarState);

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
  await loadModels();
  await refreshHistory();
  await refreshConversations();
  addMessage('assistant', 'Hola. Estoy listo para ayudarte desde la web.');
})();
