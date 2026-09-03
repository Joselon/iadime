const state = {
  sessionId: crypto.randomUUID(),
  conversation: null,
  history: [],
  models: [],
  modelProfiles: {},
  provider: '',
  selectedModel: '',
};

const messagesEl = document.getElementById('messages');
const promptEl = document.getElementById('prompt');
const composerEl = document.getElementById('composer');
const composerButtonEl = document.getElementById('sendBtn');
const keyboardBtnEl = document.getElementById('keyboardBtn');
const dictateBtnEl = document.getElementById('dictateBtn');
const attachBtnEl = document.getElementById('attachBtn');
const fileInputEl = document.getElementById('fileInput');
const sidebarToggleEl = document.getElementById('sidebarToggle');
const printFabEl = document.getElementById('printFab');
const scrollBottomBtnEl = document.getElementById('scrollBottomBtn');
const floatingControlsEl = document.querySelector('.floating-controls');
const appShellEl = document.querySelector('.app-shell');
const sidebarEl = document.getElementById('sidebar');
const modelSelectEl = document.getElementById('modelSelect');
const providerSelectEl = document.getElementById('providerSelect');
const clearBtnEl = document.getElementById('clearBtn');
const exportBtnEl = document.getElementById('exportBtn');
const printBtnEl = document.getElementById('printBtn');
const importBtnEl = document.getElementById('importBtn');
const showRulesBtnEl = document.getElementById('showRulesBtn');
const conversationNameEl = document.getElementById('conversationName');
const conversationListEl = document.getElementById('conversationList');
const conversationListCardEl = document.getElementById('conversationListCard');
const conversationRulesPanelEl = document.getElementById('conversationRulesPanel');
const conversationStatsEl = document.getElementById('conversationStats');
const modelInfoCardEl = document.getElementById('modelInfoCard');
const printHeaderEl = document.getElementById('printHeader');
let typingIndicatorEl = null;
let currentSpeech = null;
let currentVoiceButton = null;
let recognition = null;
let isRecognizing = false;
let attachedFile = null;
let sidebarOpen = window.innerWidth > 800;
let conversationsVisible = false;
let rulesVisible = false;
const MAX_ATTACHMENT_TEXT_CHARS = 12000;
const isIOSDevice = /iPad|iPhone|iPod/.test(window.navigator.userAgent)
  || (window.navigator.platform === 'MacIntel' && window.navigator.maxTouchPoints > 1);
const isStandaloneDisplay = window.navigator.standalone === true
  || window.matchMedia('(display-mode: standalone)').matches;

function getSelectedModelProfile() {
  return state.modelProfiles[state.selectedModel] || null;
}

function getComposerActionLabel() {
  const profile = getSelectedModelProfile();
  const labels = {
    image: 'Generar imagen',
    video: 'Generar vídeo',
    audio: 'Generar audio',
    research: 'Investigar',
    tts: 'Generar audio',
    transcription: 'Transcribir',
    live: 'No disponible',
  };
  return labels[profile?.kind] || 'Enviar';
}

function updateComposerForModel() {
  const profile = getSelectedModelProfile();
  const kind = profile?.kind || 'chat';
  const placeholders = {
    image: 'Describe la imagen que quieres generar (ej: "Un faro en acantilado al atardecer, estilo acuarela").',
    video: 'Describe el vídeo: escena, acción, cámara, estilo y sonido.',
    audio: 'Describe la música: género, instrumentos, ritmo, duración y ambiente.',
    research: 'Formula la investigación y especifica el tipo de informe que necesitas.',
    tts: 'Escribe el texto que quieres convertir a audio.',
    transcription: 'Adjunta un archivo de audio para transcribir.',
    live: 'Este modelo requiere WebSocket y no está disponible aún en esta interfaz.',
  };
  promptEl.placeholder = placeholders[kind] || 'Escribe tu pregunta o un comando como :help o :reset,...';
  const isUnsupported = kind === 'live';
  if (!composerButtonEl.disabled || isUnsupported) {
    composerButtonEl.disabled = isUnsupported;
    composerButtonEl.textContent = getComposerActionLabel();
  }
}

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

function focusEditableField(element, options = {}) {
  if (!element) return;
  const { preventScroll = false } = options;
  const alreadyFocused = document.activeElement === element;

  try {
    element.focus({ preventScroll });
  } catch (_error) {
    element.focus();
  }

  if (alreadyFocused) {
    return;
  }

  const end = element.value.length;
  if (typeof element.setSelectionRange === 'function') {
    try {
      element.setSelectionRange(end, end);
    } catch (_error) {
      // iOS legacy webviews can throw while moving the caret during focus changes.
    }
  }

  if (isIOSDevice && isStandaloneDisplay) {
    // iOS standalone on old devices sometimes needs a second focus in a new task to open the keyboard.
    setTimeout(() => {
      try {
        element.focus();
      } catch (_error) {
        return;
      }
      if (typeof element.setSelectionRange === 'function') {
        const position = element.value.length;
        try {
          element.setSelectionRange(position, position);
        } catch (_error) {
          // Ignore selection errors in legacy Safari.
        }
      }
    }, 0);
  }
}

function focusPrompt() {
  focusEditableField(promptEl);
}

function focusConversationName() {
  focusEditableField(conversationNameEl);
}

function formatPrintDate(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  return new Intl.DateTimeFormat('es-ES', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

function getConversationTitle() {
  return (conversationNameEl.value || state.conversation?.id || 'Conversacion').trim();
}

function updatePrintHeader() {
  if (!printHeaderEl) return;
  const summary = collectConversationSummary(state.history);
  const provider = state.provider || state.conversation?.provider || '-';
  const model = state.selectedModel || state.conversation?.model || '-';
  const updatedAt = state.conversation?.updated ? formatPrintDate(state.conversation.updated) : formatPrintDate();

  printHeaderEl.innerHTML = `
    <div class="print-header-eyebrow">iadime</div>
    <h1>${escapeHtml(getConversationTitle())}</h1>
    <p class="print-header-subtitle">Exportado para impresion el ${escapeHtml(updatedAt)}</p>
    <div class="print-meta-grid">
      <div><strong>Proveedor</strong><span>${escapeHtml(String(provider).toUpperCase())}</span></div>
      <div><strong>Modelo</strong><span>${escapeHtml(model)}</span></div>
      <div><strong>Mensajes</strong><span>${state.history.length}</span></div>
      <div><strong>Consumo</strong><span>${summary.estimatedTokens} tokens · ${formatCurrencyEur(summary.estimatedCostEur)}</span></div>
    </div>
  `;
}

function printConversation() {
  updatePrintHeader();
  window.print();
}

function scrollToConversationBottom({ smooth = true } = {}) {
  if (!messagesEl) return;
  const target = messagesEl.scrollHeight;
  if (typeof messagesEl.scrollTo === 'function') {
    try {
      messagesEl.scrollTo({
        top: target,
        behavior: smooth ? 'smooth' : 'auto',
      });
    } catch (_error) {
      messagesEl.scrollTop = target;
    }
  } else {
    messagesEl.scrollTop = target;
  }
  requestAnimationFrame(() => {
    messagesEl.scrollTop = messagesEl.scrollHeight;
  });
}

function isScrolledToBottom() {
  return messagesEl.scrollHeight - messagesEl.scrollTop <= messagesEl.clientHeight + 4;
}

function updateScrollButtonState() {
  scrollBottomBtnEl.textContent = '⇩';
  scrollBottomBtnEl.classList.remove('hidden');
  scrollBottomBtnEl.setAttribute('aria-label', 'Ir al final de la conversación');
}

function formatCurrencyEur(value) {
  return new Intl.NumberFormat('es-ES', {
    style: 'currency',
    currency: 'EUR',
    maximumFractionDigits: 4,
  }).format(Number(value || 0));
}

function estimateTokens(text) {
  const cleaned = String(text || '');
  if (!cleaned) return 0;
  return Math.max(1, Math.ceil(cleaned.length / 4));
}

function pricingFor(provider, model) {
  const pricing = {
    openai: {
      'gpt-4.1-mini': { input: 0.15, output: 0.6 },
      'gpt-4.1': { input: 2, output: 8 },
      'gpt-4o-mini': { input: 0.15, output: 0.6 },
      'gpt-4o': { input: 5, output: 15 },
    },
    gemini: {
      'gemini-2.0-flash': { input: 0.1, output: 0.4 },
      'gemini-2.0-flash-lite': { input: 0.05, output: 0.2 },
      'gemini-1.5-pro': { input: 1.25, output: 5 },
    },
  };
  const providerRates = pricing[String(provider || '').toLowerCase()] || {};
  return providerRates[String(model || '').toLowerCase()] || Object.values(providerRates)[0] || { input: 0, output: 0 };
}

function estimateTurnUsage(provider, model, prompt, answer) {
  const inputTokens = estimateTokens(prompt);
  const outputTokens = estimateTokens(answer);
  const rates = pricingFor(provider, model);
  const estimatedCostEur = ((inputTokens * rates.input) + (outputTokens * rates.output)) / 1000000;
  return {
    estimatedInputTokens: inputTokens,
    estimatedOutputTokens: outputTokens,
    estimatedTokens: inputTokens + outputTokens,
    estimatedCostEur,
  };
}

function collectConversationSummary(history) {
  return (history || []).reduce((summary, entry) => {
    summary.estimatedTokens += Number(entry.estimated_tokens || 0);
    summary.estimatedCostEur += Number(entry.estimated_cost_eur || 0);
    return summary;
  }, { estimatedTokens: 0, estimatedCostEur: 0 });
}

function renderConversationSummary(summary) {
  const totals = summary || { estimatedTokens: 0, estimatedCostEur: 0 };
  if (!conversationStatsEl) return;
  conversationStatsEl.innerHTML = `Consumo estimado: <strong>${totals.estimatedTokens}</strong> tokens · <strong>${formatCurrencyEur(totals.estimatedCostEur)}</strong>`;
}

function getCurrentRulesText() {
  return state.conversation?.system_prompt || 'Eres un asistente útil. Responde siempre en español.';
}

function renderConversationRules() {
  if (!conversationRulesPanelEl) return;
  conversationRulesPanelEl.textContent = getCurrentRulesText();
  conversationRulesPanelEl.classList.toggle('is-hidden', !rulesVisible);
  if (showRulesBtnEl) {
    showRulesBtnEl.textContent = rulesVisible ? 'Ocultar Reglas de la Conversación' : 'Mostrar Reglas de la Conversación';
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function renderModelInfo(modelName = state.selectedModel) {
  if (!modelInfoCardEl) return;
  if (!modelName) {
    modelInfoCardEl.classList.add('is-hidden');
    modelInfoCardEl.innerHTML = '';
    return;
  }

  const profile = state.modelProfiles[modelName];
  if (!profile) {
    modelInfoCardEl.classList.add('is-hidden');
    modelInfoCardEl.innerHTML = '';
    return;
  }

  const inputBadges = (profile.input || []).map((item) => `<span class="model-info-badge">Entrada: ${escapeHtml(item)}</span>`).join('');
  const outputBadges = (profile.output || []).map((item) => `<span class="model-info-badge">Salida: ${escapeHtml(item)}</span>`).join('');
  const kindLabel = profile.kind || 'chat';

  const kindWarnings = {
    image: 'Este modelo es de generación de imagen. Espera prompts visuales y devolverá una imagen, no texto conversacional.',
    video: 'Este modelo genera un vídeo de forma asíncrona. La solicitud puede tardar varios minutos.',
    audio: 'Este modelo genera música mediante la API de Interactions y devolverá un archivo de audio.',
    research: 'Este agente investiga en segundo plano y puede tardar varios minutos. Revisa las fuentes del informe.',
    tts: 'Este modelo convierte texto a audio. La reproducción en interfaz no está disponible aún.',
    live: 'Este modelo usa la Live API (WebSocket en tiempo real) y no está disponible aún en esta interfaz.',
    transcription: 'Este modelo transcribe audio. El envío de archivos de audio no está disponible aún.',
  };
  const warning = kindWarnings[kindLabel]
    ? `<p class="model-info-warning"><strong>Nota:</strong> ${escapeHtml(kindWarnings[kindLabel])}</p>`
    : '';

  modelInfoCardEl.innerHTML = `
    <h3>Modelo: ${escapeHtml(modelName)}</h3>
    <p><strong>Tipo:</strong> ${escapeHtml(kindLabel)}</p>
    <div class="model-info-badges">${inputBadges}${outputBadges}</div>
    <p><strong>Qué espera:</strong> ${escapeHtml(profile.expected_input || 'Entrada en texto')}</p>
    <p><strong>Qué devuelve:</strong> ${escapeHtml(profile.expected_output || 'Salida en texto')}</p>
    ${warning}
  `;
  modelInfoCardEl.classList.remove('is-hidden');
}

function renderMessageMetadata(metadata) {
  const provider = metadata?.provider || '';
  const model = metadata?.model || '';
  const estimatedTokens = Number(metadata?.estimated_tokens || 0);
  const estimatedCostEur = Number(metadata?.estimated_cost_eur || 0);
  const hasUsageData = estimatedTokens > 0 || estimatedCostEur > 0;

  if (!provider && !model && !hasUsageData) {
    return null;
  }

  const providerLabel = provider ? String(provider).toUpperCase() : 'PROVEEDOR';
  const footer = document.createElement('div');
  footer.className = 'message-metadata';

  const parts = [providerLabel, model || 'modelo'];
  if (hasUsageData) {
    parts.push(`${estimatedTokens} tokens`, formatCurrencyEur(estimatedCostEur));
  }
  footer.textContent = parts.join(' · ');
  return footer;
}

function renderHistoryEntries(history, summary) {
  messagesEl.innerHTML = '';
  (history || []).forEach((entry) => {
    addMessage(entry.role === 'assistant' ? 'assistant' : 'user', entry.content, {
      renderMarkdown: entry.role === 'assistant',
      metadata: entry,
    });
  });
  renderConversationSummary(summary || collectConversationSummary(history));
  updatePrintHeader();
  requestAnimationFrame(updateScrollButtonState);
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
  keyboardBtnEl.disabled = isBusy;
  dictateBtnEl.disabled = isBusy;
  attachBtnEl.disabled = isBusy;
  const profile = getSelectedModelProfile();
  const isUnsupported = profile?.kind === 'live';
  if (isBusy) {
    composerButtonEl.disabled = true;
    const busyLabels = {
      image: 'Generando…',
      video: 'Generando vídeo…',
      audio: 'Generando audio…',
      research: 'Investigando…',
      tts: 'Generando…',
      transcription: 'Procesando…',
    };
    composerButtonEl.textContent = busyLabels[profile?.kind] || 'Pensando…';
    return;
  }
  composerButtonEl.disabled = isUnsupported;
  composerButtonEl.textContent = getComposerActionLabel();
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

function addMessage(role, content, options = { renderMarkdown: true, metadata: null }) {
  const bubble = document.createElement('div');
  bubble.className = `message ${role}`;
  bubble.style.position = 'relative';
  bubble.dataset.rawContent = content;
  bubble.dataset.role = role;
  bubble.dataset.roleLabel = role === 'assistant' ? 'IA' : 'Usuario';

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

  const metadataFooter = renderMessageMetadata(options.metadata);
  if (metadataFooter) {
    bubble.appendChild(metadataFooter);
  }

  messagesEl.appendChild(bubble);
  messagesEl.scrollTop = messagesEl.scrollHeight;
  updateScrollButtonState();
}

async function syncConversation(conversation, options = {}) {
  if (!conversation) return;
  state.conversation = conversation;
  state.history = Array.isArray(conversation.history) ? conversation.history : [];
  state.provider = conversation.provider || '';
  state.selectedModel = conversation.model || '';
  if (!conversationNameEl.value) {
    conversationNameEl.value = conversation.id || '';
  }
  updatePrintHeader();
  renderConversationRules();
  providerSelectEl.value = state.provider;
  if (options.refreshModels && state.provider) {
    await loadModels(state.provider, state.selectedModel);
    return;
  }
  if (!state.provider) {
    modelSelectEl.innerHTML = '<option value="">Selecciona un proveedor primero</option>';
    modelSelectEl.disabled = true;
    return;
  }
  modelSelectEl.disabled = false;
  if (state.selectedModel) {
    modelSelectEl.value = state.selectedModel;
  }
}

async function loadModels(provider = state.provider, selectedModel = '') {
  state.provider = provider || '';
  providerSelectEl.value = state.provider;
  modelSelectEl.innerHTML = '';
  if (!state.provider) {
    state.models = [];
    state.modelProfiles = {};
    modelSelectEl.disabled = true;
    const placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = 'Selecciona un proveedor primero';
    modelSelectEl.appendChild(placeholder);
    state.selectedModel = '';
    renderModelInfo('');
    updateComposerForModel();
    renderConversationSummary(collectConversationSummary(state.history));
    return;
  }

  const response = await fetch(`/models?provider=${encodeURIComponent(state.provider)}`);
  const payload = await response.json();
  state.models = payload.models || [];
  state.modelProfiles = Object.fromEntries((payload.model_profiles || []).map((item) => [item.id, item]));
  state.provider = payload.provider || state.provider;
  providerSelectEl.value = state.provider;
  modelSelectEl.disabled = false;

  const placeholder = document.createElement('option');
  placeholder.value = '';
  placeholder.textContent = state.models.length ? 'Selecciona un modelo' : 'No hay modelos disponibles';
  modelSelectEl.appendChild(placeholder);

  state.models.forEach((model) => {
    const option = document.createElement('option');
    option.value = model;
    option.textContent = model;
    modelSelectEl.appendChild(option);
  });

  const preferredModel = selectedModel || state.selectedModel || state.models[0] || '';
  state.selectedModel = preferredModel;
  modelSelectEl.value = preferredModel;
  if (!preferredModel) {
    modelSelectEl.disabled = true;
  }
  renderModelInfo(preferredModel);
  updateComposerForModel();
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
    item.className = 'conversation-list-item';
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'load-conversation-button';
    button.textContent = name;
    button.addEventListener('click', async () => {
      await openConversation(name);
    });
    const deleteButton = document.createElement('button');
    deleteButton.type = 'button';
    deleteButton.className = 'delete-conversation-button';
    deleteButton.textContent = '🗑';
    deleteButton.title = 'Eliminar conversación';
    deleteButton.setAttribute('aria-label', `Eliminar conversación ${name}`);
    deleteButton.addEventListener('click', async (event) => {
      event.stopPropagation();
      if (!window.confirm(`¿Eliminar la conversación ${name}?`)) return;
      const response = await fetch(`/conversations?name=${encodeURIComponent(name)}`, { method: 'DELETE' });
      const deletePayload = await response.json();
      if (response.ok) {
        await refreshConversations();
        if (state.conversation?.id === name) {
          state.conversation = null;
        }
      } else {
        addMessage('assistant', deletePayload.error || 'No se pudo eliminar la conversación');
      }
    });
    item.appendChild(button);
    item.appendChild(deleteButton);
    conversationListEl.appendChild(item);
  });
  return conversations;
}

async function openConversation(name) {
  conversationNameEl.value = name;
  const response = await fetch('/import', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: state.sessionId, name }),
  });
  const payload = await response.json();
  if (payload.conversation || payload.history) {
    await syncConversation(payload.conversation || { history: payload.history || [] }, { refreshModels: true });
    renderHistoryEntries(payload.history || payload.conversation?.history || [], payload.conversation?.summary);
    return;
  }
  addMessage('assistant', payload.error || 'No se pudo cargar');
}

async function runCommand(command) {
  const response = await fetch('/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      prompt: command,
      session_id: state.sessionId,
      provider: state.provider || state.conversation?.provider || '',
      model: modelSelectEl.value || state.selectedModel || state.conversation?.model || '',
      system_prompt: state.conversation?.system_prompt,
      history: state.history,
    }),
  });
  return response.json();
}

async function renderCommandResult(command, payload) {
  await syncConversation(payload.conversation, { refreshModels: true });
  if (command === ':reset') {
    state.history = [];
    messagesEl.innerHTML = '';
    renderConversationSummary({ estimatedTokens: 0, estimatedCostEur: 0 });
  }
  addMessage('assistant', payload.answer || 'Comando ejecutado', { renderMarkdown: false });
}

async function refreshHistory(options = {}) {
  const response = await fetch(`/history?session_id=${state.sessionId}`);
  const payload = await response.json();
  if (options.syncSelection) {
    await syncConversation(payload.conversation, { refreshModels: true });
  } else {
    state.conversation = payload.conversation;
    state.history = Array.isArray(payload.history) ? payload.history : [];
  }
  renderHistoryEntries(payload.history || [], payload.conversation?.summary);
  return payload.history || [];
}

function startDictation() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    addMessage('assistant', 'El dictado por voz no está disponible en este navegador.');
    return;
  }
  recognition = new SpeechRecognition();
  recognition.lang = document.documentElement.lang || 'es-ES';
  recognition.continuous = false;
  recognition.interimResults = false;
  recognition.onresult = (event) => {
    const transcript = event.results[0][0].transcript;
    promptEl.value = (promptEl.value ? promptEl.value + ' ' : '') + transcript;
    stopDictation();
  };
  recognition.onerror = () => stopDictation();
  recognition.onend = () => stopDictation();
  recognition.start();
  isRecognizing = true;
  dictateBtnEl.classList.add('is-active');
  dictateBtnEl.title = 'Detener dictado';
  dictateBtnEl.setAttribute('aria-label', 'Detener dictado');
}

function stopDictation() {
  if (recognition) {
    recognition.abort();
    recognition = null;
  }
  isRecognizing = false;
  dictateBtnEl.classList.remove('is-active');
  dictateBtnEl.title = 'Dictado por voz';
  dictateBtnEl.setAttribute('aria-label', 'Dictado por voz');
}

keyboardBtnEl.addEventListener('click', () => {
  focusPrompt();
});

promptEl.addEventListener('pointerup', () => {
  focusPrompt();
});

promptEl.addEventListener('touchend', () => {
  focusPrompt();
}, { passive: true });

promptEl.addEventListener('click', () => {
  focusPrompt();
});

conversationNameEl.addEventListener('pointerup', () => {
  focusConversationName();
});

conversationNameEl.addEventListener('touchend', () => {
  focusConversationName();
}, { passive: true });

conversationNameEl.addEventListener('click', () => {
  focusConversationName();
});

conversationNameEl.addEventListener('input', () => {
  updatePrintHeader();
});

dictateBtnEl.addEventListener('click', () => {
  if (isRecognizing) {
    stopDictation();
  } else {
    startDictation();
  }
});

attachBtnEl.addEventListener('click', () => {
  fileInputEl.click();
});

fileInputEl.addEventListener('change', () => {
  attachedFile = fileInputEl.files[0] || null;
  if (attachedFile) {
    attachBtnEl.classList.add('is-active');
    attachBtnEl.title = `Archivo: ${attachedFile.name}`;
    attachBtnEl.setAttribute('aria-label', `Archivo adjunto: ${attachedFile.name}`);
  } else {
    attachBtnEl.classList.remove('is-active');
    attachBtnEl.title = 'Adjuntar archivo';
    attachBtnEl.setAttribute('aria-label', 'Adjuntar archivo');
  }
});

sidebarToggleEl.addEventListener('click', () => toggleSidebar());
scrollBottomBtnEl.addEventListener('click', () => {
scrollToConversationBottom({ smooth: true });
  focusPrompt();
  requestAnimationFrame(updateScrollButtonState);
});
messagesEl.addEventListener('scroll', updateScrollButtonState, { passive: true });
window.addEventListener('resize', () => {
  syncSidebarState();
  requestAnimationFrame(updateScrollButtonState);
});

function clearAttachedFile() {
  attachedFile = null;
  fileInputEl.value = '';
  attachBtnEl.classList.remove('is-active');
  attachBtnEl.title = 'Adjuntar archivo';
  attachBtnEl.setAttribute('aria-label', 'Adjuntar archivo');
}

function resolveImageDataUrl(uploadResult) {
  const fileType = String(uploadResult?.type || '').toLowerCase();
  const dataUrl = String(uploadResult?.data_url || '');
  if (!fileType.startsWith('image/')) return null;
  if (!dataUrl.startsWith('data:image/')) return null;
  return dataUrl;
}

function isTextAttachmentType(fileType) {
  const normalized = String(fileType || '').toLowerCase();
  return normalized.startsWith('text/')
    || normalized === 'application/json'
    || normalized === 'application/xml'
    || normalized === 'application/yaml'
    || normalized === 'application/x-yaml'
    || normalized === 'application/javascript';
}

function decodeDataUrlText(dataUrl) {
  const value = String(dataUrl || '');
  if (!value.startsWith('data:') || !value.includes(',')) return null;
  const [meta, encoded] = value.split(',', 2);
  if (!/;base64$/i.test(meta)) return null;
  const binary = atob(encoded);
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  const decoder = new TextDecoder('utf-8');
  return decoder.decode(bytes);
}

function resolveAttachmentText(uploadResult) {
  const fileType = String(uploadResult?.type || '');
  if (!isTextAttachmentType(fileType)) return null;
  const decoded = decodeDataUrlText(uploadResult?.data_url);
  if (!decoded || !decoded.trim()) return null;
  if (decoded.length <= MAX_ATTACHMENT_TEXT_CHARS) return decoded;
  return `${decoded.slice(0, MAX_ATTACHMENT_TEXT_CHARS)}\n\n[...contenido truncado por longitud...]`;
}

async function uploadFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = async (e) => {
      const dataUrl = e.target.result;
      const base64 = dataUrl.split(',')[1];
      try {
        const response = await fetch('/upload', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name: file.name, type: file.type, data: base64 }),
        });
        const payload = await response.json();
        if (!response.ok) {
          reject(new Error(payload.error || 'Error al subir el archivo'));
          return;
        }
        resolve({ ...payload, data_url: payload.data_url || dataUrl });
      } catch (err) {
        reject(err);
      }
    };
    reader.onerror = () => reject(new Error('Error al leer el archivo'));
    reader.readAsDataURL(file);
  });
}

composerEl.addEventListener('submit', async (event) => {
  event.preventDefault();
  const prompt = promptEl.value.trim();
  if (!prompt || composerButtonEl.disabled) return;

  if (prompt.startsWith(':')) {
    promptEl.value = '';
    promptEl.style.height = '';
    setComposerBusy(true);
    try {
      const payload = await runCommand(prompt);
      if (payload.answer) {
        await renderCommandResult(prompt, payload);
      } else {
        addMessage('assistant', payload.error || 'No se pudo ejecutar el comando');
      }
    } catch (error) {
      addMessage('assistant', 'No se pudo completar la solicitud.');
    } finally {
      setComposerBusy(false);
    }
    return;
  }

  if (!state.provider || !modelSelectEl.value) {
    addMessage('assistant', 'Selecciona un proveedor y un modelo antes de enviar el mensaje.');
    return;
  }

  let uploadedFileUrl = null;
  let uploadedDataUrl = null;
  let uploadedAttachmentText = null;
  let uploadedAttachmentName = '';
  if (attachedFile) {
    setComposerBusy(true);
    try {
      const result = await uploadFile(attachedFile);
      uploadedFileUrl = result.url;
      uploadedDataUrl = resolveImageDataUrl(result);
      uploadedAttachmentText = resolveAttachmentText(result);
      uploadedAttachmentName = String(result.name || attachedFile.name || 'archivo');
    } catch (err) {
      addMessage('assistant', `No se pudo subir el archivo: ${err.message}`);
      setComposerBusy(false);
      return;
    }
    clearAttachedFile();
  }

  const effectivePrompt = uploadedFileUrl ? `${prompt}\n\n[Archivo adjunto: ${uploadedFileUrl}]` : prompt;
  const providerPrompt = uploadedAttachmentText
    ? `${effectivePrompt}\n\n[Contenido del archivo adjunto: ${uploadedAttachmentName}]\n---\n${uploadedAttachmentText}\n---`
    : effectivePrompt;

  const optimisticMetadata = estimateTurnUsage(state.provider, modelSelectEl.value, providerPrompt, '');
  addMessage('user', effectivePrompt, {
    metadata: {
      provider: state.provider,
      model: modelSelectEl.value,
      estimated_tokens: optimisticMetadata.estimatedInputTokens,
      estimated_cost_eur: 0,
    },
  });
  promptEl.value = '';
  promptEl.style.height = '';
  showTypingIndicator();
  setComposerBusy(true);

  try {
    const response = await fetch('/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        prompt: effectivePrompt,
        session_id: state.sessionId,
        model: modelSelectEl.value,
        provider: state.provider,
        history: state.history,
        prompt_with_attachment: providerPrompt !== effectivePrompt ? providerPrompt : undefined,
        image_url: uploadedDataUrl || undefined,
      }),
    });
    const payload = await response.json();
    if (payload.answer) {
      await syncConversation(payload.conversation, { refreshModels: true });
      await refreshHistory();
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
  state.selectedModel = '';
  document.body.dataset.provider = state.provider;
  await loadModels(state.provider);
  updatePrintHeader();
});

modelSelectEl.addEventListener('change', () => {
  state.selectedModel = modelSelectEl.value;
  renderModelInfo(state.selectedModel);
  updateComposerForModel();
  updatePrintHeader();
});

clearBtnEl.addEventListener('click', async () => {
  if (!state.provider || !modelSelectEl.value) {
    state.history = [];
    messagesEl.innerHTML = '';
    renderConversationSummary({ estimatedTokens: 0, estimatedCostEur: 0 });
    return;
  }

  setComposerBusy(true);
  try {
    const payload = await runCommand(':reset');
    if (payload.answer) {
      await renderCommandResult(':reset', payload);
    } else {
      state.history = [];
      messagesEl.innerHTML = '';
      renderConversationSummary({ estimatedTokens: 0, estimatedCostEur: 0 });
    }
  } catch (error) {
    addMessage('assistant', 'No se pudo reiniciar el contexto.');
  } finally {
    setComposerBusy(false);
  }
});

exportBtnEl.addEventListener('click', async () => {
  const name = (conversationNameEl.value || 'conversacion').trim();
  const response = await fetch('/export', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ session_id: state.sessionId, name, history: state.history }),
  });
  const payload = await response.json();
  await syncConversation(payload.conversation, { refreshModels: true });
  if (payload.conversations) {
    await refreshConversations();
  }
  addMessage('assistant', payload.message || 'Conversación guardada');
});

printBtnEl.addEventListener('click', printConversation);
printFabEl.addEventListener('click', printConversation);
window.addEventListener('beforeprint', updatePrintHeader);

importBtnEl.addEventListener('click', async () => {
  conversationsVisible = !conversationsVisible;
  conversationListCardEl.classList.toggle('is-collapsed', !conversationsVisible);
  importBtnEl.textContent = conversationsVisible ? '⌃' : '⌄';
  importBtnEl.setAttribute('aria-label', conversationsVisible ? 'Ocultar conversaciones guardadas' : 'Mostrar conversaciones guardadas');
  if (conversationsVisible) {
    await refreshConversations();
  }
});

showRulesBtnEl.addEventListener('click', () => {
  rulesVisible = !rulesVisible;
  renderConversationRules();
});

(async () => {
  syncSidebarState();
  requestAnimationFrame(updateScrollButtonState);
  renderConversationSummary({ estimatedTokens: 0, estimatedCostEur: 0 });
  renderConversationRules();
  updateComposerForModel();
  updatePrintHeader();
  await refreshHistory();
  addMessage('assistant', 'Hola. Estoy listo para ayudarte desde la web.');
})();
