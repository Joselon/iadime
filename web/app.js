const state = {
  sessionId: crypto.randomUUID(),
  history: [],
  models: [],
  provider: 'openai',
};

const messagesEl = document.getElementById('messages');
const promptEl = document.getElementById('prompt');
const composerEl = document.getElementById('composer');
const modelSelectEl = document.getElementById('modelSelect');
const providerSelectEl = document.getElementById('providerSelect');
const clearBtnEl = document.getElementById('clearBtn');
const exportBtnEl = document.getElementById('exportBtn');
const importBtnEl = document.getElementById('importBtn');
const conversationNameEl = document.getElementById('conversationName');
const conversationListEl = document.getElementById('conversationList');

function renderMermaidBlocks(container) {
  if (!window.mermaid || typeof window.mermaid.run !== 'function') {
    return;
  }
  const nodes = container.querySelectorAll('.mermaid');
  if (!nodes.length) {
    return;
  }
  window.mermaid.run({ nodes: Array.from(nodes) });
}

function renderMarkdown(content) {
  const container = document.createElement('div');
  container.className = 'message-body';
  const lines = String(content || '').split(/\r?\n/);
  const htmlParts = [];
  let inCode = false;
  let inMermaid = false;
  let codeBuffer = [];
  let codeLang = '';

  const flushCode = () => {
    if (!inCode) return;
    const codeText = codeBuffer.join('\n');
    if (inMermaid) {
      htmlParts.push(`<div class="mermaid">${codeText}</div>`);
    } else {
      const langClass = codeLang ? ` class="language-${codeLang}"` : '';
      htmlParts.push(`<pre><code${langClass}>${escapeHtml(codeText)}</code></pre>`);
    }
    codeBuffer = [];
    codeLang = '';
    inCode = false;
    inMermaid = false;
  };

  const escapeHtml = (value) => value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  const renderInline = (value) => escapeHtml(value)
    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    .replace(/\*(.*?)\*/g, '<em>$1</em>')
    .replace(/`([^`]+)`/g, '<code>$1</code>');

  lines.forEach((line) => {
    if (/^```mermaid\s*$/.test(line)) {
      flushCode();
      inCode = true;
      inMermaid = true;
      return;
    }
    if (/^```/.test(line)) {
      if (inCode) {
        flushCode();
      } else {
        codeLang = line.slice(3).trim();
        inCode = true;
        inMermaid = false;
      }
      return;
    }
    if (inCode) {
      codeBuffer.push(line);
      return;
    }
    if (/^###\s+/.test(line)) {
      htmlParts.push(`<h3>${renderInline(line.slice(4))}</h3>`);
    } else if (/^##\s+/.test(line)) {
      htmlParts.push(`<h2>${renderInline(line.slice(3))}</h2>`);
    } else if (/^#\s+/.test(line)) {
      htmlParts.push(`<h1>${renderInline(line.slice(2))}</h1>`);
    } else if (line.trim()) {
      htmlParts.push(`<p>${renderInline(line)}</p>`);
    } else {
      htmlParts.push('<p></p>');
    }
  });

  flushCode();
  container.innerHTML = htmlParts.join('');
  renderMermaidBlocks(container);
  return container;
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

composerEl.addEventListener('submit', async (event) => {
  event.preventDefault();
  const prompt = promptEl.value.trim();
  if (!prompt) return;
  addMessage('user', prompt);
  promptEl.value = '';
  promptEl.style.height = '';
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
  await loadModels();
  await refreshHistory();
  await refreshConversations();
  addMessage('assistant', 'Hola. Estoy listo para ayudarte desde la web.');
})();
