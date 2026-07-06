// ranch_ledger frontend app
// Connects to the Express API (server.js) for bovine data

const API_BASE = window.location.origin.includes('localhost') 
    ? 'http://localhost:3000' 
    : '';

let currentBovineId = null;

// Search for a bovine by name or ID
async function searchBovine(query) {
    try {
        const response = await fetch(`${API_BASE}/bovines/${query}`);
        if (!response.ok) throw new Error(t('notFound'));
        const bovine = await response.json();
        displayBovine(bovine);
        await loadLifecycleEvents(bovine.id);
    } catch (error) {
        alert(t('notFound'));
        console.error(error);
    }
}

function displayBovine(bovine) {
    currentBovineId = bovine.id;
    
    document.getElementById('bovineDetails').classList.remove('hidden');
    document.getElementById('lifecycleEvents').classList.remove('hidden');
    document.getElementById('qrSection').classList.remove('hidden');
    document.getElementById('fracSection').classList.remove('hidden');
    
    document.getElementById('bovineName').textContent = bovine.name || '-';
    document.getElementById('bovineBreed').textContent = bovine.breed || '-';
    document.getElementById('bovineAge').textContent = `${bovine.age} ${t('yearsOld')}`;
    document.getElementById('bovineLocation').textContent = bovine.location || '-';
    document.getElementById('bovineOwner').textContent = bovine.owner ? `${bovine.owner.slice(0,6)}...${bovine.owner.slice(-4)}` : '-';
    document.getElementById('bovineCountry').textContent = bovine.countryCode || '-';
    document.getElementById('bovineNationalId').textContent = bovine.nationalId || '-';
    document.getElementById('bovineEarTag').textContent = bovine.earTag || '-';
}

async function loadLifecycleEvents(bovineId) {
    try {
        // Load vaccines
        const vaccinesRes = await fetch(`${API_BASE}/bovines/${bovineId}/vaccines`);
        if (vaccinesRes.ok) {
            const vaccines = await vaccinesRes.json();
            displayVaccines(vaccines);
        }
        
        // Load movements
        const movementsRes = await fetch(`${API_BASE}/bovines/${bovineId}/movements`);
        if (movementsRes.ok) {
            const movements = await movementsRes.json();
            displayMovements(movements);
        }
        
        // Load feeds
        const feedsRes = await fetch(`${API_BASE}/bovines/${bovineId}/feeds`);
        if (feedsRes.ok) {
            const feeds = await feedsRes.json();
            displayFeeds(feeds);
        }
        
        // Load health exams
        const healthRes = await fetch(`${API_BASE}/bovines/${bovineId}/health-exams`);
        if (healthRes.ok) {
            const exams = await healthRes.json();
            displayHealthExams(exams);
        }
    } catch (error) {
        console.error('Failed to load lifecycle events:', error);
    }
}

function displayVaccines(vaccines) {
    const list = document.getElementById('vaccinesList');
    list.innerHTML = '';
    if (!vaccines || vaccines.length === 0) {
        list.innerHTML = `<p class="text-gray-400 text-sm">${t('noData')}</p>`;
        return;
    }
    vaccines.forEach(v => {
        const date = new Date(v.date * 1000).toLocaleDateString(currentLang === 'pt-BR' ? 'pt-BR' : 'en-US');
        list.innerHTML += `<div class="text-sm border-l-2 border-green-400 pl-2 py-1">${v.name} — ${date}</div>`;
    });
}

function displayMovements(movements) {
    const list = document.getElementById('movementsList');
    list.innerHTML = '';
    if (!movements || movements.length === 0) {
        list.innerHTML = `<p class="text-gray-400 text-sm">${t('noData')}</p>`;
        return;
    }
    movements.forEach(m => {
        const date = new Date(m.date * 1000).toLocaleDateString(currentLang === 'pt-BR' ? 'pt-BR' : 'en-US');
        list.innerHTML += `<div class="text-sm border-l-2 border-blue-400 pl-2 py-1">${t('fromLocation')}: ${m.fromLocation} → ${t('toLocation')}: ${m.toLocation} — ${date}</div>`;
    });
}

function displayFeeds(feeds) {
    const list = document.getElementById('feedsList');
    list.innerHTML = '';
    if (!feeds || feeds.length === 0) {
        list.innerHTML = `<p class="text-gray-400 text-sm">${t('noData')}</p>`;
        return;
    }
    feeds.forEach(f => {
        const date = new Date(f.date * 1000).toLocaleDateString(currentLang === 'pt-BR' ? 'pt-BR' : 'en-US');
        list.innerHTML += `<div class="text-sm border-l-2 border-yellow-400 pl-2 py-1">${f.foodType} (${t('origin')}: ${f.origin}) — ${date}</div>`;
    });
}

function displayHealthExams(exams) {
    const list = document.getElementById('healthExamsList');
    list.innerHTML = '';
    if (!exams || exams.length === 0) {
        list.innerHTML = `<p class="text-gray-400 text-sm">${t('noData')}</p>`;
        return;
    }
    exams.forEach(e => {
        const date = new Date(e.date * 1000).toLocaleDateString(currentLang === 'pt-BR' ? 'pt-BR' : 'en-US');
        list.innerHTML += `<div class="text-sm border-l-2 border-red-400 pl-2 py-1">${e.examType}: ${e.result} — ${date}</div>`;
    });
}

// Event listeners
document.getElementById('searchBtn').addEventListener('click', () => {
    const query = document.getElementById('searchInput').value.trim();
    if (query) searchBovine(query);
});

document.getElementById('searchInput').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
        const query = document.getElementById('searchInput').value.trim();
        if (query) searchBovine(query);
    }
});

document.getElementById('buySharesBtn').addEventListener('click', () => {
    const amount = document.getElementById('buySharesInput').value;
    if (amount && currentBovineId) {
        alert(`Buying ${amount} shares for bovine #${currentBovineId}...`);
        // TODO: Call FractionalizationManager.buyShares()
    }
});

document.getElementById('redeemSharesBtn').addEventListener('click', () => {
    if (currentBovineId) {
        alert(`Redeeming shares for bovine #${currentBovineId}...`);
        // TODO: Call FractionalizationManager.redeemShares()
    }
});