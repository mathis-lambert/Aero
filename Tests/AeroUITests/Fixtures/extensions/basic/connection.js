document.getElementById('provider').addEventListener('click', () => {
    const provider = new URLSearchParams(location.search).get('provider');
    location.href = provider + '/extension-return.html?target=' + encodeURIComponent(chrome.runtime.getURL('return.html'));
});
