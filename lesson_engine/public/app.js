const elements = {
  health: document.getElementById('health'), createForm: document.getElementById('createForm'), questionText: document.getElementById('questionText'),
  questionImage: document.getElementById('questionImage'), uploadBox: document.getElementById('uploadBox'), fileName: document.getElementById('fileName'),
  createButton: document.getElementById('createButton'), statusCard: document.getElementById('statusCard'), statusTitle: document.getElementById('statusTitle'),
  statusPercent: document.getElementById('statusPercent'), statusBar: document.getElementById('statusBar'), statusMessage: document.getElementById('statusMessage'),
  statusError: document.getElementById('statusError'), visualWarning: document.getElementById('visualWarning'), regenerateButton: document.getElementById('regenerateButton'), downloadButton: document.getElementById('downloadButton'),
  downloadTopButton: document.getElementById('downloadTopButton'), openButton: document.getElementById('openButton'), refreshButton: document.getElementById('refreshButton'),
  historyList: document.getElementById('historyList'), previewTitle: document.getElementById('previewTitle'), previewFrame: document.getElementById('previewFrame'),
  previewPlaceholder: document.getElementById('previewPlaceholder')
};
let currentProjectId = null;
let currentRecord = null;
let eventSource = null;
const stageNames = { queued:'等待开始', extracting:'正在读题', solving:'正在求解', planning:'正在排课', verifying:'正在复核', rendering:'正在生成 HTML', visual_check:'正在检查视觉布局', repairing:'正在自动修复布局', done:'生成完成', failed:'生成失败' };

async function request(url, options) {
  let response;
  try {
    response = await fetch(url, options);
  } catch (error) {
    throw new Error('无法连接本地服务。请确认 npm start 正在运行，然后刷新页面。');
  }
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || `请求失败：${response.status}`);
  return payload;
}

async function loadHealth() {
  try {
    const data = await request('/api/health');
    elements.health.classList.add(data.providers.deepseek ? 'is-ok' : 'is-warn');
    elements.health.replaceChildren();
    const dot = document.createElement('span'); dot.className = 'health-dot';
    const text = document.createElement('span');
    text.textContent = data.providers.aliyun ? 'DeepSeek 已配置 · 千问视觉已配置' : 'DeepSeek 已配置 · 千问视觉未配置';
    elements.health.append(dot, text);
  } catch (error) { elements.health.classList.add('is-warn'); elements.health.textContent = error.message; }
}

async function loadProjects() {
  const { projects } = await request('/api/projects');
  elements.historyList.replaceChildren();
  if (!projects.length) {
    const empty = document.createElement('div'); empty.className = 'empty-state'; empty.textContent = '还没有生成记录。'; elements.historyList.appendChild(empty); return;
  }
  projects.forEach((project) => {
    const button = document.createElement('button'); button.type = 'button'; button.className = 'history-item'; button.classList.toggle('is-active', project.id === currentProjectId);
    const title = document.createElement('strong'); title.textContent = project.title || '未命名题目';
    const meta = document.createElement('span'); meta.textContent = `${project.subject || '综合'} · ${stageNames[project.stage] || project.stage}${project.visualStatus === 'warning' ? ' · 视觉警告' : ''}`;
    const time = document.createElement('small'); time.textContent = new Date(project.createdAt).toLocaleString('zh-CN');
    button.append(title, meta, time); button.addEventListener('click', () => selectProject(project.id)); elements.historyList.appendChild(button);
  });
}

async function selectProject(id) {
  currentProjectId = id;
  const { project } = await request(`/api/projects/${id}`);
  currentRecord = project;
  renderStatus(project, stageNames[project.stage] || project.stage);
  elements.previewTitle.textContent = project.title || '讲解预览';
  await loadProjects();
  if (project.status === 'done') { showPreview(); connectEvents(id); }
  else if (project.status === 'failed') showError(project.error || '生成失败');
  else connectEvents(id);
}

function connectEvents(projectId) {
  if (eventSource) eventSource.close();
  eventSource = new EventSource(`/api/projects/${projectId}/events`);
  eventSource.onmessage = async (event) => {
    const data = JSON.parse(event.data);
    if (!data.record) return;
    currentRecord = data.record; renderStatus(data.record, data.message); await loadProjects();
    if (data.type === 'done') { showPreview(); eventSource.close(); eventSource = null; }
    if (data.type === 'error') { showError(data.record.error || data.message); eventSource.close(); eventSource = null; }
  };
  eventSource.onerror = () => { eventSource?.close(); eventSource = null; };
}

function renderStatus(record, message) {
  elements.statusCard.classList.remove('is-hidden');
  elements.statusTitle.textContent = stageNames[record.stage] || '正在生成';
  elements.statusPercent.textContent = `${record.progress || 0}%`;
  elements.statusBar.style.width = `${record.progress || 0}%`;
  elements.statusMessage.textContent = message || '请稍候…';
  elements.statusError.classList.add('is-hidden');
  elements.regenerateButton.disabled = record.status === 'running';
  elements.downloadButton.disabled = record.status !== 'done';
  elements.downloadTopButton.disabled = record.status !== 'done';
  elements.openButton.disabled = record.status !== 'done';
  elements.previewTitle.textContent = record.title || '讲解预览';
}

function showError(message) { elements.statusError.textContent = message; elements.statusError.classList.remove('is-hidden'); }
function showPreview() {
  if (!currentProjectId) return;
  elements.previewPlaceholder.classList.add('is-hidden');
  elements.previewFrame.src = `/api/projects/${currentProjectId}/html?v=${Date.now()}`;
  elements.downloadButton.disabled = false; elements.downloadTopButton.disabled = false; elements.openButton.disabled = false;
}

elements.createForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const text = elements.questionText.value.trim();
  const file = elements.questionImage.files?.[0];
  if (!text && !file) { renderStatus({stage:'failed',progress:100,status:'failed'}, '请输入题目文字或上传题目图片'); return; }
  const formData = new FormData(); if (text) formData.append('text', text); if (file) formData.append('image', file, file.name);
  elements.createButton.disabled = true;
  elements.statusCard.classList.remove('is-hidden'); elements.statusTitle.textContent = '正在创建项目'; elements.statusPercent.textContent = '0%'; elements.statusBar.style.width = '0%'; elements.statusMessage.textContent = '正在上传并启动自动生成…'; elements.statusError.classList.add('is-hidden');
  try { const result = await request('/api/projects', { method:'POST', body:formData }); currentProjectId = result.id; await selectProject(result.id); await loadProjects(); }
  catch (error) { showError(error.message); }
  finally { elements.createButton.disabled = false; }
});

elements.questionImage.addEventListener('change', () => {
  const file = elements.questionImage.files?.[0]; elements.uploadBox.classList.toggle('is-selected', Boolean(file));
  elements.fileName.textContent = file ? file.name : '支持 JPG、PNG、WebP，最大 12 MB';
});
elements.regenerateButton.addEventListener('click', async () => {
  if (!currentProjectId) return;
  try { await request(`/api/projects/${currentProjectId}/regenerate`, { method:'POST' }); await selectProject(currentProjectId); }
  catch (error) { showError(error.message); }
});
elements.downloadButton.addEventListener('click', () => { if (currentProjectId) location.href = `/api/projects/${currentProjectId}/download`; });
elements.downloadTopButton.addEventListener('click', () => { if (currentProjectId) location.href = `/api/projects/${currentProjectId}/download`; });
elements.openButton.addEventListener('click', () => { if (currentProjectId) window.open(`/api/projects/${currentProjectId}/html`, '_blank', 'noopener'); });
elements.refreshButton.addEventListener('click', loadProjects);
loadHealth();
loadProjects().catch((error) => { elements.historyList.textContent = error.message; });
