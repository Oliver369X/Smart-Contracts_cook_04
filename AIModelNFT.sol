// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AIModelNFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;
    
    // Token de Mantle
    IERC20 public mantleToken;
    
    // Sistema de precios en USD (con 6 decimales)
    uint256 public usdPricePerImage = 50000; // $0.50 USD por imagen
    uint256 public usdPricePerFineTuning = 50000000; // $50.00 USD por fine-tuning
    uint256 public usdPricePerNFT = 200000; // $0.20 USD por NFT
    
    // Precio de MNT en USD (con 6 decimales) - Actualizable
    uint256 public mntUsdPrice = 1100000; // $1.10 USD por MNT
    
    // Mappings principales
    mapping(string => uint8) existingModelURIs;
    mapping(uint256 => address) public modelCreator;
    mapping(uint256 => uint256) public modelUsagePrice;
    mapping(uint256 => uint256) public totalUsageCount;
    mapping(uint256 => uint256) public totalEarnings;
    mapping(address => uint256) public creatorEarnings;
    
    // Variables de estado
    address public marketOwner;
    uint256 public marketFee = 20; // 20% para marketplace
    uint256 public creatorRoyalty = 70; // 70% para creador
    uint256 public supply = 0;
    uint256 public totalUsageTransactions = 0;
    
    // Sistema de niveles
    mapping(address => uint256) public creatorLevel; // 1-5 niveles
    mapping(uint256 => uint256) public levelMultiplier; // Multiplicadores por nivel
    
    // Eventos
    event ModelMinted(
        uint256 tokenId,
        address indexed creator,
        uint256 usagePrice,
        string modelURI,
        string modelType,
        uint256 timestamp
    );
    
    event ModelUsed(
        uint256 tokenId,
        address indexed user,
        address indexed creator,
        uint256 usagePrice,
        uint256 creatorRoyalty,
        uint256 marketFee,
        uint256 timestamp
    );
    
    event ModelSold(
        uint256 tokenId,
        address indexed from,
        address indexed to,
        uint256 price,
        uint256 timestamp
    );
    
    event CreatorLevelUp(
        address indexed creator,
        uint256 newLevel,
        uint256 timestamp
    );
    
    event PriceUpdated(
        string priceType,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );
    
    // Estructura de datos
    struct AIModel {
        uint256 tokenId;
        address creator;
        uint256 usagePrice;
        uint256 totalUsageCount;
        uint256 totalEarnings;
        string title;
        string description;
        string modelURI;
        string modelType;
        string modelParams;
        uint256 timestamp;
        bool isActive;
        uint256 creatorLevel;
        uint256 popularityScore;
    }
    
    // Array de modelos
    AIModel[] public aiModels;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _mantleToken
    ) ERC721(_name, _symbol) {
        marketOwner = msg.sender;
        mantleToken = IERC20(_mantleToken);
        
        // Inicializar multiplicadores de nivel
        levelMultiplier[1] = 100; // 1x
        levelMultiplier[2] = 120; // 1.2x
        levelMultiplier[3] = 150; // 1.5x
        levelMultiplier[4] = 200; // 2x
        levelMultiplier[5] = 300; // 3x
    }
    
    // Función para calcular precio en MNT basado en USD
    function getMntPriceForUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount * 10**18) / mntUsdPrice;
    }
    
    // Función para obtener precio de imagen en MNT
    function getImagePriceInMnt() public view returns (uint256) {
        return getMntPriceForUsd(usdPricePerImage);
    }
    
    // Función para obtener precio de fine-tuning en MNT
    function getFineTuningPriceInMnt() public view returns (uint256) {
        return getMntPriceForUsd(usdPricePerFineTuning);
    }
    
    // Función para obtener precio de NFT en MNT
    function getNftPriceInMnt() public view returns (uint256) {
        return getMntPriceForUsd(usdPricePerNFT);
    }
    
    // Función para mintear
    function mintAIModel(
        string memory title,
        string memory description,
        uint256 usagePrice,
        string memory modelURI,
        string memory modelType,
        string memory modelParams
    ) external nonReentrant {
        require(existingModelURIs[modelURI] == 0, "This AI model is already minted!");
        require(msg.sender != owner(), "Marketplace owner cannot mint models!");
        require(usagePrice > 0, "Usage price must be greater than 0!");
        
        supply++;
        
        // Calcular nivel del creador
        uint256 currentLevel = creatorLevel[msg.sender];
        if (currentLevel == 0) {
            currentLevel = 1;
            creatorLevel[msg.sender] = 1;
        }
        
        aiModels.push(AIModel({
            tokenId: supply,
            creator: msg.sender,
            usagePrice: usagePrice,
            totalUsageCount: 0,
            totalEarnings: 0,
            title: title,
            description: description,
            modelURI: modelURI,
            modelType: modelType,
            modelParams: modelParams,
            timestamp: block.timestamp,
            isActive: true,
            creatorLevel: currentLevel,
            popularityScore: 0
        }));
        
        modelCreator[supply] = msg.sender;
        modelUsagePrice[supply] = usagePrice;
        
        emit ModelMinted(supply, msg.sender, usagePrice, modelURI, modelType, block.timestamp);
        
        _safeMint(msg.sender, supply);
        existingModelURIs[modelURI] = 1;
    }
    
    // Función para usar modelo
    function useAIModel(uint256 tokenId, uint256 amount) external nonReentrant {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        require(aiModels[tokenId - 1].isActive, "Model is not active!");
        require(amount >= aiModels[tokenId - 1].usagePrice, "Insufficient MNT payment for model usage!");
        
        address creator = aiModels[tokenId - 1].creator;
        uint256 usagePrice = aiModels[tokenId - 1].usagePrice;
        uint256 modelCreatorLevel = aiModels[tokenId - 1].creatorLevel;
        
        // Transferir MNT al contrato
        require(mantleToken.transferFrom(msg.sender, address(this), amount), "MNT transfer failed");
        
        // Calcular royalties con multiplicador de nivel
        uint256 baseCreatorRoyalty = (usagePrice * creatorRoyalty) / 100;
        uint256 levelBonus = (baseCreatorRoyalty * (levelMultiplier[modelCreatorLevel] - 100)) / 100;
        uint256 totalCreatorRoyalty = baseCreatorRoyalty + levelBonus;
        uint256 marketFeeAmount = (usagePrice * marketFee) / 100;
        
        // Transferir pagos en MNT
        if (totalCreatorRoyalty > 0) {
            require(mantleToken.transfer(creator, totalCreatorRoyalty), "Creator payment failed");
            creatorEarnings[creator] += totalCreatorRoyalty;
        }
        
        if (marketFeeAmount > 0) {
            require(mantleToken.transfer(marketOwner, marketFeeAmount), "Market payment failed");
        }
        
        // Devolver exceso
        uint256 totalPaid = totalCreatorRoyalty + marketFeeAmount;
        if (amount > totalPaid) {
            require(mantleToken.transfer(msg.sender, amount - totalPaid), "Refund failed");
        }
        
        // Actualizar estadísticas
        aiModels[tokenId - 1].totalUsageCount++;
        aiModels[tokenId - 1].totalEarnings += usagePrice;
        aiModels[tokenId - 1].popularityScore += 10;
        totalUsageCount[tokenId]++;
        totalEarnings[tokenId] += usagePrice;
        totalUsageTransactions++;
        
        // Verificar si el creador sube de nivel
        checkCreatorLevelUp(creator);
        
        emit ModelUsed(
            tokenId,
            msg.sender,
            creator,
            usagePrice,
            totalCreatorRoyalty,
            marketFeeAmount,
            block.timestamp
        );
    }
    
    // Función para comprar NFT
    function buyAIModel(uint256 tokenId, uint256 amount) external nonReentrant {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        require(aiModels[tokenId - 1].isActive, "Model is not active!");
        
        address currentOwner = ownerOf(tokenId);
        require(msg.sender != currentOwner, "You already own this model!");
        require(amount > 0, "Invalid purchase price!");
        
        // Transferir MNT al contrato
        require(mantleToken.transferFrom(msg.sender, address(this), amount), "MNT transfer failed");
        
        // Transferir el NFT
        _transfer(currentOwner, msg.sender, tokenId);
        
        // Calcular royalties
        address originalCreator = aiModels[tokenId - 1].creator;
        uint256 creatorRoyaltyAmount = (amount * 25) / 100; // 25% para creador original
        uint256 marketFeeAmount = (amount * 15) / 100; // 15% para marketplace
        uint256 sellerAmount = amount - creatorRoyaltyAmount - marketFeeAmount; // 60% para vendedor
        
        // Transferir pagos en MNT
        if (creatorRoyaltyAmount > 0) {
            require(mantleToken.transfer(originalCreator, creatorRoyaltyAmount), "Creator payment failed");
            creatorEarnings[originalCreator] += creatorRoyaltyAmount;
        }
        
        if (marketFeeAmount > 0) {
            require(mantleToken.transfer(marketOwner, marketFeeAmount), "Market payment failed");
        }
        
        if (sellerAmount > 0) {
            require(mantleToken.transfer(currentOwner, sellerAmount), "Seller payment failed");
        }
        
        emit ModelSold(tokenId, currentOwner, msg.sender, amount, block.timestamp);
    }
    
    // Función para cambiar precio de uso
    function changeUsagePrice(uint256 tokenId, uint256 newUsagePrice) external {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        require(msg.sender == aiModels[tokenId - 1].creator, "Only creator can change usage price!");
        require(newUsagePrice > 0, "Usage price must be greater than 0!");
        
        aiModels[tokenId - 1].usagePrice = newUsagePrice;
        modelUsagePrice[tokenId] = newUsagePrice;
    }
    
    // Función para activar/desactivar modelo
    function toggleModelStatus(uint256 tokenId) external {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        require(msg.sender == aiModels[tokenId - 1].creator, "Only creator can toggle model status!");
        
        aiModels[tokenId - 1].isActive = !aiModels[tokenId - 1].isActive;
    }
    
    // Funciones de consulta
    function getAIModel(uint256 tokenId) external view returns (AIModel memory) {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        return aiModels[tokenId - 1];
    }
    
    function getAllAIModels() external view returns (AIModel[] memory) {
        return aiModels;
    }
    
    function getActiveAIModels() external view returns (AIModel[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < aiModels.length; i++) {
            if (aiModels[i].isActive) {
                activeCount++;
            }
        }
        
        AIModel[] memory activeModels = new AIModel[](activeCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < aiModels.length; i++) {
            if (aiModels[i].isActive) {
                activeModels[currentIndex] = aiModels[i];
                currentIndex++;
            }
        }
        
        return activeModels;
    }
    
    function getCreatorEarnings(address creator) external view returns (uint256) {
        return creatorEarnings[creator];
    }
    
    function getModelUsageStats(uint256 tokenId) external view returns (uint256 usageCount, uint256 modelTotalEarnings) {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        return (totalUsageCount[tokenId], totalEarnings[tokenId]);
    }
    
    // Funciones administrativas
    function changeMarketFee(uint256 _marketFee) external onlyOwner {
        marketFee = _marketFee;
    }
    
    function changeCreatorRoyalty(uint256 _creatorRoyalty) external onlyOwner {
        creatorRoyalty = _creatorRoyalty;
    }
    
    function setMantleToken(address _mantleToken) external onlyOwner {
        mantleToken = IERC20(_mantleToken);
    }
    
    // Funciones para actualizar precios USD
    function updateMntUsdPrice(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = mntUsdPrice;
        mntUsdPrice = newPrice;
        emit PriceUpdated("MNT_USD", oldPrice, newPrice, block.timestamp);
    }
    
    function updateUsdPricePerImage(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = usdPricePerImage;
        usdPricePerImage = newPrice;
        emit PriceUpdated("IMAGE_USD", oldPrice, newPrice, block.timestamp);
    }
    
    function updateUsdPricePerFineTuning(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = usdPricePerFineTuning;
        usdPricePerFineTuning = newPrice;
        emit PriceUpdated("FINETUNING_USD", oldPrice, newPrice, block.timestamp);
    }
    
    function updateUsdPricePerNFT(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = usdPricePerNFT;
        usdPricePerNFT = newPrice;
        emit PriceUpdated("NFT_USD", oldPrice, newPrice, block.timestamp);
    }
    
    // Función interna para verificar nivel
    function checkCreatorLevelUp(address creator) internal {
        uint256 currentLevel = creatorLevel[creator];
        uint256 creatorTotalEarnings = creatorEarnings[creator];
        
        // Lógica de subida de nivel basada en ganancias
        if (creatorTotalEarnings >= 100 * 10**18 && currentLevel < 2) {
            creatorLevel[creator] = 2;
            emit CreatorLevelUp(creator, 2, block.timestamp);
        } else if (creatorTotalEarnings >= 500 * 10**18 && currentLevel < 3) {
            creatorLevel[creator] = 3;
            emit CreatorLevelUp(creator, 3, block.timestamp);
        } else if (creatorTotalEarnings >= 1000 * 10**18 && currentLevel < 4) {
            creatorLevel[creator] = 4;
            emit CreatorLevelUp(creator, 4, block.timestamp);
        } else if (creatorTotalEarnings >= 5000 * 10**18 && currentLevel < 5) {
            creatorLevel[creator] = 5;
            emit CreatorLevelUp(creator, 5, block.timestamp);
        }
    }
    
    // Función para retirar ganancias
    function withdrawEarnings() external nonReentrant {
        uint256 amount = creatorEarnings[msg.sender];
        require(amount > 0, "No earnings to withdraw");
        
        creatorEarnings[msg.sender] = 0;
        require(mantleToken.transfer(msg.sender, amount), "Withdrawal failed");
    }
}
