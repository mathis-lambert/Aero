chrome.runtime.sendMessage({fixture: 'returned'}).then(reply => {
    if (reply.received === 'returned') document.getElementById('worker').textContent = 'Worker connected after return';
});
