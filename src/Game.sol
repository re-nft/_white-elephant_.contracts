// SPDX-License-Identifier: MIT

/// @author Nazariy Vavryk [nazariy@inbox.ru] - reNFT Labs [https://twitter.com/renftlabs]
// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

/** Holiday season NFT game. Players buy tickets to win the NFTs
 * in the prize pool. Every ticket buyer will win an NFT.
 * -------------------------------------------------------------
 *                      RULES OF THE GAME
 * -------------------------------------------------------------
 * 1. Players buy tickets before Jan 3rd 2021 23:59:59 GMT.
 * 2. Only 255 players will participate in the game.
 * 1. Players take turns to unwrap or steal.
 * 2. Each player can only steal once and be stolen from once.
 * 3. Each player has 3 hours to take the turn.
 * 4. If the player fails to take action, they lose their ability
 * to steal and an NFT is randomly assigned to them.
 */
contract Game is Ownable, ERC721Holder, VRFConsumerBase, ReentrancyGuard {
    struct Nft {
        address adr;
        uint256 id;
    }
    struct Players {
        address[256] addresses;
        mapping(address => bool) contains;
        uint8 numPlayers;
    }
    struct Entropies {
        uint256[8] vals;
        uint8 numEntropies;
    }

    /// @dev Chainlink related
    address private chainlinkVrfCoordinator = 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9;
    address private chainlinkLinkToken = 0xa36085F69e2889c224210F603D836748e7dC0088;
    bytes32 private chainlinkKeyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
    uint256 private chainlinkCallFee = 0.1 * 10**18;
    uint256 public ticketPrice = 0.0001 ether;
    /// @dev before this date, you can be buying tickets. After this date, unwrapping begins
    /// @dev 2021 January 3rd 23:59:59 GMT
    uint32 public timeBeforeGameStart = 1609718399;

    /// order in which the players take turns. This gets set after gameStart once everyone has randomness associated to them
    /// an example of this is 231, 1, 21, 3, ...; the numbers signify the addresses at
    /// indices 231, 1, 3 and so on from the players array. We avoid having a map
    /// of indices like 1, 2, 3 and so on to addresses which are then duplicated
    /// as well in the players array. Note that this is 1-indexed! First player is not index 0, but 1.
    /// This is done such that the maps of steals "swaps" and "spaws" would not signify a player at index
    /// 0 (default value of uninitialised uint8).
    /// Interpretation of this is that if at index 0 in playersOrder we have index 3
    /// then that means that player players.addresses[3] is the one to go first
    uint8[255] public playersOrder;
    /// Chainlink entropies
    Entropies private entropies;
    /// this array tracks the addresses of all the players that will participate in the game
    /// these guys bought the ticket before `gameStart`
    Players public players;

    /// to keep track of all the deposited NFTs
    Nft[255] public nfts;
    /// address on the left stole from address on the right
    /// think of it as a swap of NFTs
    /// once again the address is the index in players array
    mapping(uint8 => uint8) public swaps;
    /// efficient reverse lookup at the expense of extra storage, forgive me
    mapping(uint8 => uint8) public spaws;
    /// for onlyOwner use only, this lets the contract know who is allowed to
    /// deposit the NFTs into the prize pool
    mapping(address => bool) public depositors;
    /// flag that indicates if the game is ready to start
    /// after people bought the tickets, owners initialize the
    /// contract with chainlink entropy. Before this is done
    /// the game cannot begin
    bool private initComplete = false;
    /// tracks the last time a valid steal or unwrap call was made
    /// this serves to signal if any of the players missed their turn
    /// when a player misses their turn, they forego the ability to
    /// steal from someone who unwrapped before them
    /// Initially this gets set in the initEnd by owner, when they complete
    /// the initialization of the game
    uint32 private lastAction;
    /// this is how much time in seconds each player has to unwrap
    /// or steal. If they do not act, they forego their ability
    /// to steal. 3 hours each player times 256 players max is 768 hours
    /// which equates to 32 days.
    uint16 public thinkTime = 10800;
    /// index from playersOrder of current unwrapper / stealer
    uint8 public currPlayer = 0;

    /// @dev at this point we have a way to track all of the players - players
    /// @dev we have the NFT that each player will win (unless stolen from) - playersOrder
    /// @dev we have a way to determine which NFT the player will get if stolen from - swaps
    /// @dev at the expense of storage, O(1) check if player was stolen from - spaws

    modifier beforeGameStart() {
        require(now < timeBeforeGameStart, "game has now begun");
        _;
    }

    modifier afterGameStart() {
        /// @dev I have read miners can manipulate block time for up to 900 seconds
        /// @dev I am creating two times here to ensure that there is no overlap
        /// @dev To avoid a situation where both are true
        /// @dev 2 * 900 = 1800 gives extra cushion
        require(now > timeBeforeGameStart + 1800, "game has not started yet");
        require(initComplete, "game has not initialized yet");
        _;
    }

    modifier onlyWhitelisted() {
        require(depositors[msg.sender], "you are not allowed to deposit");
        _;
    }

    modifier youShallNotPatheth(uint8 missed) {
        uint256 currTime = now;
        require(currTime > lastAction, "timestamps are incorrect");
        uint256 elapsed = currTime - lastAction;
        uint256 playersSkipped = elapsed / thinkTime;
        // someone has skipped their turn. We track this on the front-end
        if (missed != 0) {
            require(playersSkipped > 0, "zero players skipped");
            require(playersSkipped < 255, "too many players skipped");
            require(playersSkipped == missed, "playersSkipped not eq missed");
            require(currPlayer < 256, "currPlayer exceeds 255");
        } else {
            require(playersSkipped == 0, "playersSkipped not zero");
        }
        require(players.addresses[playersOrder[currPlayer + missed]] == msg.sender, "not your turn");
        _;
    }

    /// Add who is allowed to deposit NFTs with this function
    /// All addresses that are not whitelisted will not be
    /// allowed to deposit.
    function addDepositors(address[] calldata ds) external onlyOwner {
        for (uint256 i = 0; i < ds.length; i++) {
            depositors[ds[i]] = true;
        }
    }

    constructor() public VRFConsumerBase(chainlinkVrfCoordinator, chainlinkLinkToken) {
        // keyHash = CHAINLINK_REQUEST_KEY_HASH;
        // fee = CHAINLINK_LINK_CALL_FEE;
        depositors[0x465DCa9995D6c2a81A9Be80fBCeD5a770dEE3daE] = true;
        depositors[0x426923E98e347158D5C471a9391edaEa95516473] = true;
        // depositors[0x63A556c75443b176b5A4078e929e38bEb37a1ff2] = true;
    }

    function deposit(ERC721[] calldata _nfts, uint256[] calldata tokenIds) public onlyWhitelisted {
        require(_nfts.length == tokenIds.length, "variable lengths");
        for (uint256 i = 0; i < _nfts.length; i++) {
            _nfts[i].transferFrom(msg.sender, address(this), tokenIds[i]);
        }
    }

    function buyTicket() public payable beforeGameStart nonReentrant {
        require(msg.value >= ticketPrice, "sent ether too low");
        require(players.numPlayers < 256, "total number of players reached");
        require(players.contains[msg.sender] == false, "cant buy more");
        players.contains[msg.sender] = true;
        // at 0-index we have address(0)
        players.addresses[players.numPlayers + 1] = msg.sender;
        players.numPlayers++;
    }

    /// @param missed - how many players missed their turn since lastAction
    function unwrap(uint8 missed) external afterGameStart nonReentrant youShallNotPatheth(missed) {
        currPlayer += missed + 1;
        lastAction = uint32(now);
    }

    /// @param sender - index from players arr that you are stealing from
    /// @param from - index from players who to steal from
    /// @param missed - how many players missed their turn since lastAction
    function steal(
        uint8 sender,
        uint8 from,
        uint8 missed
    ) external afterGameStart nonReentrant youShallNotPatheth(missed) {
        require(players.addresses[sender] == msg.sender, "sender is not valid");
        require(players.addresses[playersOrder[currPlayer]] == players.addresses[sender], "not your order");
        require(spaws[from] == 0, "cant steal from them again");
        require(swaps[sender] == 0, "you cant steal again. You can in Verkhovna Rada.");
        swaps[sender] = from;
        spaws[from] = sender;
        currPlayer += missed + 1;
        lastAction = uint32(now);
    }

    // function finito() external onlyOwner {
    // take into account the steals, the skips and unwraps
    // distribute the NFT prizes to their rightful owners
    // }

    /// Will revert the safeTransfer
    /// on transfer nothing happens, the NFT is not added to the prize pool
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public override returns (bytes4) {
        revert("we are saving you your NFT, you are welcome");
    }

    /// we slice up Chainlink's uint256 into 32 chunks to obtaink 32 uint8 vals
    /// each one now represents the order of the ticket buyers, which also
    /// represents the NFT that they will unwrap (unless swapped with)
    function initStart(uint8 numCalls, uint256[] calldata ourEntropy) external onlyOwner {
        require(initComplete == false, "cannot init start again");
        require(now > timeBeforeGameStart + 1800, "game has not started yet");
        require(numCalls == ourEntropy.length, "incorrect entropy size");
        for (uint256 i = 0; i < numCalls; i++) {
            getRandomness(ourEntropy[i]);
        }
    }

    /// After slicing the Chainlink entropy off-chain, give back the randomness
    /// result here. The technique which will be used must be voiced prior to the
    /// game, obviously
    function initEnd(uint8[255] calldata _playersOrder, uint32 _lastAction) external onlyOwner {
        require(now > timeBeforeGameStart + 1800, "game has not started yet");
        require(_playersOrder.length == players.numPlayers, "incorrect len");
        playersOrder = _playersOrder;
        lastAction = _lastAction;
        initComplete = true;
    }

    /// Randomness is queried afterGameStart but before initComplete (flag)
    function getRandomness(uint256 ourEntropy) internal returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= chainlinkCallFee, "not enough LINK");
        requestId = requestRandomness(chainlinkKeyHash, chainlinkCallFee, ourEntropy);
    }

    /// Gets called by Chainlink
    function fulfillRandomness(bytes32, uint256 randomness) internal override {
        entropies.vals[entropies.numEntropies] = randomness;
        entropies.numEntropies++;
    }

    /// @dev utility read funcs

    /// @dev admin funcs
    function setTicketPrice(uint256 v) external onlyOwner {
        ticketPrice = v;
    }

    // todo: withdrawal functions
    function player(uint8 i) external view returns (address, uint8) {
        return (players.addresses[i], players.numPlayers);
    }

    function entropy(uint8 i) external view onlyOwner returns (uint256, uint8) {
        return (entropies.vals[i], entropies.numEntropies);
    }
}
