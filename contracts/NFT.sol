// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFT is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using Strings for uint256;

  // ----- Token config -----
  // Total number of NFT that can be minted
  uint256 public maxSupply;
  // Root of the IPFS metadata store
  string public baseURI = "";
  string public baseExtension = ".json";
  // Current number of tokens
  uint256 public numTokens = 0;

  // Mapping which token we already handed out
  uint256[] private indices;

  // Constructor. We set the symbol and name and start with sa
  constructor() ERC721("NFTToken", "NFT") {
    maxSupply = 1000;
    indices = new uint256[](1000);
  }

  receive() external payable {
    this;
  }

  // Way to change the baseUri,
  // this is usefull if we ever need to switch the IPFS gateway for example
  function setBaseURI(string memory _uri) external onlyOwner {
    baseURI = _uri;
  }

  /// @notice Mint a number of tokens and send them to sender
  /// @param _number How many tokens to mint
  function mint(uint256 _number) external nonReentrant onlyOwner {
    uint256 supply = uint256(totalSupply());
    require(supply + _number <= maxSupply, "Not enough NFT left.");
    _internalMint(_number, msg.sender);
  }

  // ----- Helper functions -----
  /// @notice Get all token ids belonging to an address
  /// @param _owner Wallet to find tokens of
  /// @return  Array of the owned token ids
  function walletOfOwner(address _owner) external view returns (uint256[] memory) {
    uint256 tokenCount = balanceOf(_owner);

    uint256[] memory tokensId = new uint256[](tokenCount);
    for (uint256 i; i < tokenCount; i++) {
      tokensId[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokensId;
  }

  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    require(_exists(tokenId), "ERC721: URI query for nonexistent token");

    string memory currentBaseURI = _baseURI();
    return
      bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  /// @notice Select a number of tokens and send them to a receiver
  /// @param _number How many tokens to mint
  /// @param _receiver Address to mint the tokens to
  function _internalMint(uint256 _number, address _receiver) internal {
    uint256 tokenID;

    for (uint256 i; i < _number; i++) {
      tokenID = numTokens;
      numTokens++;

      _safeMint(_receiver, tokenID);
    }
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override(ERC721, ERC721Enumerable) {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  // ----- ERC721 functions -----
  function _baseURI() internal view override(ERC721) returns (string memory) {
    return baseURI;
  }
}
