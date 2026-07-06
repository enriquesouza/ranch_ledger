const translations = {
    'pt-BR': {
        title: 'ranch_ledger',
        subtitle: 'Rastreabilidade Bovina na Blockchain',
        searchTitle: 'Buscar Animal',
        searchPlaceholder: 'Nome ou ID do bovino',
        searchBtn: 'Buscar',
        detailsTitle: 'Detalhes do Animal',
        name: 'Nome',
        breed: 'Raça',
        age: 'Idade',
        location: 'Localização',
        owner: 'Proprietário',
        country: 'País',
        nationalId: 'ID Nacional',
        earTag: 'Brinco',
        lifecycleTitle: 'Histórico de Vida',
        vaccines: 'Vacinas',
        movements: 'Movimentações',
        feeds: 'Alimentação',
        healthExams: 'Exames de Saúde',
        qrTitle: 'Código QR para Consumidor',
        qrDescription: 'Escaneie para ver o histórico completo deste animal',
        fracTitle: 'Fração de Propriedade',
        totalShares: 'Total de Cotas',
        sharePrice: 'Preço por Cota',
        yourShares: 'Suas Cotas',
        buyShares: 'Comprar Cotas',
        redeemShares: 'Resgatar',
        footer: 'ranch_ledger — Rastreabilidade bovina na blockchain | MIT License',
        notFound: 'Animal não encontrado',
        connectWallet: 'Conectar Carteira',
        walletConnected: 'Carteira Conectada',
        yearsOld: 'anos',
        noData: 'Sem dados',
        abattoirTitle: 'Processamento de Abatedouro',
        abattoir: 'Abatedouro',
        processing: 'Processamento',
        date: 'Data',
        fromLocation: 'De',
        toLocation: 'Para',
        foodType: 'Tipo de Alimento',
        origin: 'Origem',
        quantity: 'Quantidade',
        examType: 'Tipo de Exame',
        result: 'Resultado'
    },
    'en': {
        title: 'ranch_ledger',
        subtitle: 'Bovine Traceability on the Blockchain',
        searchTitle: 'Search Animal',
        searchPlaceholder: 'Bovine name or ID',
        searchBtn: 'Search',
        detailsTitle: 'Animal Details',
        name: 'Name',
        breed: 'Breed',
        age: 'Age',
        location: 'Location',
        owner: 'Owner',
        country: 'Country',
        nationalId: 'National ID',
        earTag: 'Ear Tag',
        lifecycleTitle: 'Lifecycle History',
        vaccines: 'Vaccines',
        movements: 'Movements',
        feeds: 'Feed',
        healthExams: 'Health Exams',
        qrTitle: 'Consumer QR Code',
        qrDescription: 'Scan to see the full history of this animal',
        fracTitle: 'Ownership Shares',
        totalShares: 'Total Shares',
        sharePrice: 'Price per Share',
        yourShares: 'Your Shares',
        buyShares: 'Buy Shares',
        redeemShares: 'Redeem',
        footer: 'ranch_ledger — Bovine traceability on the blockchain | MIT License',
        notFound: 'Animal not found',
        connectWallet: 'Connect Wallet',
        walletConnected: 'Wallet Connected',
        yearsOld: 'years old',
        noData: 'No data',
        abattoirTitle: 'Abattoir Processing',
        abattoir: 'Abattoir',
        processing: 'Processing',
        date: 'Date',
        fromLocation: 'From',
        toLocation: 'To',
        foodType: 'Food Type',
        origin: 'Origin',
        quantity: 'Quantity',
        examType: 'Exam Type',
        result: 'Result'
    }
};

let currentLang = 'pt-BR';

function setLanguage(lang) {
    currentLang = lang;
    document.documentElement.lang = lang;
    
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.getAttribute('data-i18n');
        if (translations[lang][key]) {
            el.textContent = translations[lang][key];
        }
    });
    
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        const key = el.getAttribute('data-i18n-placeholder');
        if (translations[lang][key]) {
            el.placeholder = translations[lang][key];
        }
    });
    
    const toggleBtn = document.getElementById('langToggle');
    if (lang === 'pt-BR') {
        toggleBtn.textContent = '🇧🇷 PT-BR';
    } else {
        toggleBtn.textContent = '🇺🇸 EN';
    }
}

function t(key) {
    return translations[currentLang][key] || key;
}

document.getElementById('langToggle').addEventListener('click', () => {
    setLanguage(currentLang === 'pt-BR' ? 'en' : 'pt-BR');
});

// Initialize with Portuguese
setLanguage('pt-BR');