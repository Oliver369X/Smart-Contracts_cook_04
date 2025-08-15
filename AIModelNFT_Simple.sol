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
    
    // Variables básicas
    mapping(uint256 => address) public modelCreator;
    mapping(uint256 => uint256) public modelUsagePrice;
    mapping(uint256 => uint256) public totalUsageCount;
    mapping(address => uint256) public creatorEarnings;
    
    // Estado
    address public marketOwner;
    uint256 public marketFee = 20;
    uint256 public creatorRoyalty = 70;
    uint256 public supply = 0;
    
    // Eventos
    event ModelMinted(uint256 tokenId, address creator, uint256 usagePrice, string modelURI);
    event ModelUsed(uint256 tokenId, address user, address creator, uint256 usagePrice);
    event ModelSold(uint256 tokenId, address from, address to, uint256 price);
    
    // Estructura simplificada
    struct AIModel {
        uint256 tokenId;
        address creator;
        uint256 usagePrice;
        string title;
        string modelURI;
        bool isActive;
    }
    
    AIModel[] public aiModels;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _mantleToken
    ) ERC721(_name, _symbol) {
        marketOwner = msg.sender;
        mantleToken = IERC20(_mantleToken);
    }
    
    // Función simplificada para mintear
    function mintAIModel(
        string memory title,
        uint256 usagePrice,
        string memory modelURI
    ) external nonReentrant {
        require(usagePrice > 0, "Usage price must be greater than 0!");
        
        supply++;
        
        aiModels.push(AIModel({
            tokenId: supply,
            creator: msg.sender,
            usagePrice: usagePrice,
            title: title,
            modelURI: modelURI,
            isActive: true
        }));
        
        modelCreator[supply] = msg.sender;
        modelUsagePrice[supply] = usagePrice;
        
        emit ModelMinted(supply, msg.sender, usagePrice, modelURI);
        
        _safeMint(msg.sender, supply);
    }
    
    // Función simplificada para usar modelo
    function useAIModel(uint256 tokenId, uint256 amount) external nonReentrant {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        require(aiModels[tokenId - 1].isActive, "Model is not active!");
        require(amount >= aiModels[tokenId - 1].usagePrice, "Insufficient payment!");
        
        address creator = aiModels[tokenId - 1].creator;
        uint256 usagePrice = aiModels[tokenId - 1].usagePrice;
        
        // Transferir MNT
        require(mantleToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Calcular pagos
        uint256 creatorAmount = (usagePrice * creatorRoyalty) / 100;
        uint256 marketAmount = (usagePrice * marketFee) / 100;
        
        // Transferir pagos
        if (creatorAmount > 0) {
            require(mantleToken.transfer(creator, creatorAmount), "Creator payment failed");
            creatorEarnings[creator] += creatorAmount;
        }
        
        if (marketAmount > 0) {
            require(mantleToken.transfer(marketOwner, marketAmount), "Market payment failed");
        }
        
        // Devolver exceso
        uint256 totalPaid = creatorAmount + marketAmount;
        if (amount > totalPaid) {
            require(mantleToken.transfer(msg.sender, amount - totalPaid), "Refund failed");
        }
        
        // Actualizar estadísticas
        aiModels[tokenId - 1].usagePrice = usagePrice;
        totalUsageCount[tokenId]++;
        
        emit ModelUsed(tokenId, msg.sender, creator, usagePrice);
    }
    
    // Función para comprar NFT
    function buyAIModel(uint256 tokenId, uint256 amount) external nonReentrant {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        
        address currentOwner = ownerOf(tokenId);
        require(msg.sender != currentOwner, "You already own this model!");
        
        // Transferir MNT
        require(mantleToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Transferir NFT
        _transfer(currentOwner, msg.sender, tokenId);
        
        // Calcular royalties
        address originalCreator = aiModels[tokenId - 1].creator;
        uint256 creatorAmount = (amount * 25) / 100;
        uint256 marketAmount = (amount * 15) / 100;
        uint256 sellerAmount = amount - creatorAmount - marketAmount;
        
        // Transferir pagos
        if (creatorAmount > 0) {
            require(mantleToken.transfer(originalCreator, creatorAmount), "Creator payment failed");
            creatorEarnings[originalCreator] += creatorAmount;
        }
        
        if (marketAmount > 0) {
            require(mantleToken.transfer(marketOwner, marketAmount), "Market payment failed");
        }
        
        if (sellerAmount > 0) {
            require(mantleToken.transfer(currentOwner, sellerAmount), "Seller payment failed");
        }
        
        emit ModelSold(tokenId, currentOwner, msg.sender, amount);
    }
    
    // Funciones de consulta
    function getAIModel(uint256 tokenId) external view returns (AIModel memory) {
        require(tokenId > 0 && tokenId <= supply, "Invalid token ID!");
        return aiModels[tokenId - 1];
    }
    
    function getCreatorEarnings(address creator) external view returns (uint256) {
        return creatorEarnings[creator];
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
    
    // Función para retirar ganancias
    function withdrawEarnings() external nonReentrant {
        uint256 amount = creatorEarnings[msg.sender];
        require(amount > 0, "No earnings to withdraw");
        
        creatorEarnings[msg.sender] = 0;
        require(mantleToken.transfer(msg.sender, amount), "Withdrawal failed");
    }
}
