interface Asset {
  name: string;
  browser_download_url: string;
  size: number;
}

interface Release {
  tag_name: string;
  html_url: string;
  published_at: string;
  assets: Asset[];
}

interface Platform {
  os: 'macos' | 'linux' | 'windows';
  arch: 'arm64' | 'x64';
  label: string;
  assetPattern: RegExp;
  icon: string;
}

const PLATFORMS: Platform[] = [
  { os: 'macos', arch: 'arm64', label: 'macOS (Apple Silicon)', assetPattern: /macos-arm64$/, icon: '' },
  { os: 'macos', arch: 'x64', label: 'macOS (Intel)', assetPattern: /macos-x64$/, icon: '' },
  { os: 'linux', arch: 'x64', label: 'Linux (x64)', assetPattern: /linux-x64$/, icon: '' },
  { os: 'linux', arch: 'arm64', label: 'Linux (ARM64)', assetPattern: /linux-arm64$/, icon: '' },
  { os: 'linux', arch: 'x64', label: 'Linux AppImage (x64)', assetPattern: /linux-x86_64\.AppImage$/, icon: '' },
  { os: 'linux', arch: 'arm64', label: 'Linux AppImage (ARM64)', assetPattern: /linux-aarch64\.AppImage$/, icon: '' },
  { os: 'windows', arch: 'x64', label: 'Windows (x64)', assetPattern: /windows-x64\.exe$/, icon: '' },
];

function detectPlatform(): Platform {
  const ua = navigator.userAgent.toLowerCase();
  const platform = navigator.platform?.toLowerCase() || '';
  
  // Detect OS
  let os: 'macos' | 'linux' | 'windows' = 'linux';
  if (ua.includes('mac') || platform.includes('mac')) {
    os = 'macos';
  } else if (ua.includes('win') || platform.includes('win')) {
    os = 'windows';
  }
  
  // Detect architecture (best effort - browsers obscure this)
  let arch: 'arm64' | 'x64' = 'x64';
  if (os === 'macos') {
    // Check for Apple Silicon indicators
    // Note: Chrome on M1 reports as Intel, so we default to ARM64 for modern Macs
    const isAppleSilicon = 
      ua.includes('arm') || 
      platform.includes('arm') ||
      // @ts-ignore - experimental API
      (navigator.userAgentData?.platform === 'macOS' && navigator.userAgentData?.architecture === 'arm');
    
    // Default to ARM64 for macOS as most new Macs are Apple Silicon
    arch = isAppleSilicon || !ua.includes('intel') ? 'arm64' : 'x64';
  } else if (os === 'linux') {
    if (ua.includes('aarch64') || ua.includes('arm64')) {
      arch = 'arm64';
    }
  }
  
  return PLATFORMS.find(p => p.os === os && p.arch === arch) || PLATFORMS[0];
}

function formatSize(bytes: number): string {
  const mb = bytes / (1024 * 1024);
  return `${mb.toFixed(1)} MB`;
}

async function fetchLatestRelease(): Promise<Release> {
  const cacheKey = 'clarissa-release';
  const cacheTTL = 5 * 60 * 1000; // 5 minutes
  
  const cached = localStorage.getItem(cacheKey);
  if (cached) {
    const { data, timestamp } = JSON.parse(cached);
    if (Date.now() - timestamp < cacheTTL) {
      return data;
    }
  }
  
  const response = await fetch('https://api.github.com/repos/cameronrye/clarissa/releases/latest');
  if (!response.ok) throw new Error('Failed to fetch release');
  
  const data = await response.json();
  localStorage.setItem(cacheKey, JSON.stringify({ data, timestamp: Date.now() }));
  return data;
}

function renderDownloadSection(release: Release, detectedPlatform: Platform): string {
  const detectedAsset = release.assets.find(a => detectedPlatform.assetPattern.test(a.name));
  const version = release.tag_name;
  const date = new Date(release.published_at).toLocaleDateString('en-US', { 
    year: 'numeric', month: 'short', day: 'numeric' 
  });

  const otherPlatforms = PLATFORMS
    .filter(p => p !== detectedPlatform)
    .map(p => {
      const asset = release.assets.find(a => p.assetPattern.test(a.name));
      if (!asset) return '';
      return `<a href="${asset.browser_download_url}" class="platform-link">${p.label}<span class="size">${formatSize(asset.size)}</span></a>`;
    })
    .filter(Boolean)
    .join('');

  return `
    <div class="primary-download">
      <div class="detected-platform">
        <span class="detected-label">Detected platform:</span>
        <span class="platform-name">${detectedPlatform.label}</span>
      </div>
      ${detectedAsset ? `
        <a href="${detectedAsset.browser_download_url}" class="btn btn-primary download-btn">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
            <polyline points="7 10 12 15 17 10"></polyline>
            <line x1="12" y1="15" x2="12" y2="3"></line>
          </svg>
          Download ${version}
          <span class="size">${formatSize(detectedAsset.size)}</span>
        </a>
      ` : '<p class="error">Binary not available for this platform</p>'}
      <p class="version-info">
        Version ${version} &middot; Released ${date} &middot; 
        <a href="${release.html_url}" target="_blank" rel="noopener">Release notes</a>
      </p>
    </div>
    <details class="other-platforms">
      <summary>Download for other platforms</summary>
      <div class="platform-list">${otherPlatforms}</div>
    </details>
  `;
}

function renderError(message: string): string {
  return `
    <div class="error-state">
      <p>${message}</p>
      <p>Download directly from <a href="https://github.com/cameronrye/clarissa/releases" target="_blank" rel="noopener">GitHub Releases</a></p>
    </div>
  `;
}

export async function initDownloadPage(): Promise<void> {
  const section = document.getElementById('download-section');
  if (!section) return;

  try {
    const release = await fetchLatestRelease();
    const detectedPlatform = detectPlatform();
    section.innerHTML = renderDownloadSection(release, detectedPlatform);

    // Inject styles for dynamically rendered content
    const style = document.createElement('style');
    style.textContent = `
      .primary-download { text-align: center; margin-bottom: 2rem; }
      .detected-platform { margin-bottom: 1.5rem; color: var(--color-text-muted); font-size: 0.9rem; }
      .platform-name { color: var(--color-text); font-weight: 600; margin-left: 0.5rem; }
      .download-btn { font-size: 1.1rem; padding: 1rem 2rem; }
      .download-btn .size { opacity: 0.7; font-size: 0.85rem; margin-left: 0.5rem; }
      .version-info { margin-top: 1rem; font-size: 0.85rem; color: var(--color-text-muted); }
      .other-platforms { background: var(--color-bg-secondary); border: 1px solid var(--color-border); border-radius: 8px; padding: 1rem; }
      .other-platforms summary { cursor: pointer; color: var(--color-text-muted); font-size: 0.9rem; }
      .other-platforms summary:hover { color: var(--color-text); }
      .platform-list { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 0.75rem; margin-top: 1rem; }
      .platform-link { display: flex; justify-content: space-between; align-items: center; background: var(--color-bg-tertiary); border: 1px solid var(--color-border); border-radius: 6px; padding: 0.75rem 1rem; font-size: 0.9rem; transition: border-color 0.2s; }
      .platform-link:hover { border-color: var(--color-purple); color: var(--color-text); }
      .platform-link .size { color: var(--color-text-muted); font-size: 0.8rem; }
      .error-state { text-align: center; padding: 2rem; color: var(--color-text-muted); }
      .error { color: #f87171; }
    `;
    document.head.appendChild(style);
  } catch (error) {
    section.innerHTML = renderError('Unable to fetch latest release.');
  }
}

