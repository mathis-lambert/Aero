document.getElementById("grow").addEventListener("click", () => {
    document.body.style.width = "1200px";
    document.body.style.height = "900px";
});
document.getElementById('connection').addEventListener('click', async () => {
    const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
    const url = chrome.runtime.getURL('connection.html') + '?provider=' + encodeURIComponent(new URL(tab.url).origin);
    await chrome.tabs.create({url, active: true});
    window.close();
});
