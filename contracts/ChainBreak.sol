// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IChainBreak.sol";
import "./Utility.sol";
// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract ChainBreak is IChainBreak {
    event Borrowed(address borrower, address lender, Loan _loan);
    event Confirmed(address borrower, address lender, Loan _loan);
    event LoanFill(address borrower, address lender, Loan _loan);

    enum LoanStatus {Pending, Confirmed, Closed}

    struct Loan {
        uint amount;
        uint closedAmount;
        uint32 ttl;
        uint32 createdAt;
        uint32 closedAt;
        LoanStatus status;
        bool autoClose;
        string description;
    }

    struct User {
        // just for indexing
        address[] lenders;
        // only 1 loan for person for mvp
        // lender => loan
        mapping (address => Loan) loans;
        // back index
        address[] borrowers;
    }

    struct UserLoan {
        address user;
        Loan loan;
    }

    address[] private usersIndex;
    mapping (address => User) private users;

    uint public constant BUILDER_FEE = 0.001 ether;

    constructor() {}

    function getUserData(address user) external view returns (
        // loans lender -> user
        // loans user -> borrower
        UserLoan[] memory fromUsers,
        UserLoan[] memory toUsers
    ) {
        fromUsers = new UserLoan[](users[user].lenders.length);
        toUsers = new UserLoan[](users[user].borrowers.length);

        for (uint i = 0; i < fromUsers.length; i++) {
            address lender = users[user].lenders[i];
            Loan memory loan = users[user].loans[lender];
            fromUsers[i] = UserLoan(lender, loan);
        }

        for (uint i = 0; i < toUsers.length; i++) {
            address borrower = users[user].borrowers[i];
            Loan memory loan = users[borrower].loans[user];
            toUsers[i] = UserLoan(borrower, loan);
        }
    }

    function borrow(address lender, uint amount, uint32 ttl, bool autoClose, string calldata description) external payable {
        require (amount > 0, "ChainBreak::resolveLoanCircuit: zero amount");
        require (msg.value == BUILDER_FEE, "ChainBreak::borrow: incorrect msg. value");
        require (users[msg.sender].loans[lender].amount == 0, "ChainBreak::borrow: already borrowed");

        Loan memory _loan = Loan({
            amount : amount,
            closedAmount : 0,
            autoClose : autoClose,
            closedAt : 0,
            createdAt : uint32(block.timestamp),
            status : LoanStatus.Pending,
            description : description,
            ttl : ttl
        });
        users[msg.sender].loans[lender] = _loan;
        users[msg.sender].lenders.push(lender);
        users[lender].borrowers.push(msg.sender);

        emit Borrowed(msg.sender, lender, _loan);
    }

    function lend(address borrower, uint amount, uint32 ttl, string calldata description) external {
        require (amount > 0, "ChainBreak::resolveLoanCircuit: zero amount");
        require (users[borrower].loans[msg.sender].amount == 0, "ChainBreak::borrow: already borrowed");

        Loan memory _loan = Loan({
            amount : amount,
            closedAmount : 0,
            autoClose : false,
            closedAt : 0,
            createdAt : uint32(block.timestamp),
            status : LoanStatus.Pending,
            description : description,
            ttl : ttl
        });
        users[borrower].loans[msg.sender] = _loan;
        users[borrower].lenders.push(msg.sender);
        users[msg.sender].borrowers.push(borrower);

        emit Borrowed(borrower, msg.sender, _loan);
    }

    function confirmLoanByBorrower(address lender, bool autoClose) external payable {
        require (msg.value == BUILDER_FEE, "ChainBreak::borrow: incorrect msg. value");
        require (users[msg.sender].loans[lender].amount > 0, "ChainBreak::borrow: no loan");
        require (users[msg.sender].loans[lender].status == LoanStatus.Pending, "ChainBreak::borrow: bad status");

        Loan memory _loan = users[msg.sender].loans[lender];
        _loan.status = LoanStatus.Confirmed;
        _loan.autoClose = autoClose;
        users[msg.sender].loans[lender] = _loan;

        emit Confirmed(msg.sender, lender, _loan);
    }

    function confirmLoanByLender(address borrower) external {
        require (users[borrower].loans[msg.sender].amount > 0, "ChainBreak::borrow: no loan");
        require (users[borrower].loans[msg.sender].status == LoanStatus.Pending, "ChainBreak::borrow: bad status");

        Loan memory _loan = users[borrower].loans[msg.sender];
        _loan.status = LoanStatus.Confirmed;
        users[borrower].loans[msg.sender] = _loan;

        emit Confirmed(borrower, msg.sender, _loan);
    }


    function resolveLoanCircuit(address[] calldata circuit, uint amount) external {
        require (amount > 0, "ChainBreak::resolveLoanCircuit: zero amount");
        require (circuit[0] == circuit[circuit.length - 1], "ChainBreak::resolveLoanCircuit: incorrect circuit");

        uint160[] memory addrs = new uint160[](circuit.length);
        for (uint i = 0; i < circuit.length; i++) {
            addrs[i] = uint160(circuit[i]);
        }

        addrs = Utility.sort(addrs);
        for (uint i = 0; i < addrs.length - 1; i++) {
            require (addrs[i] < addrs[i + 1], "ChainBreak::resolveLoanCircuit: duplicate elems");
        }

        for (uint i = 0; i < circuit.length - 1; i++) {
            address borrower = circuit[i];
            address lender = circuit[i + 1];

            Loan memory _loan = users[borrower].loans[lender];
            require (_loan.autoClose, "ChainBreak::resolveLoanCircuit: auto close not permitted");
            require (_loan.amount - _loan.closedAmount >= amount, "ChainBreak::resolveLoanCircuit: bad amount");
            require (_loan.status == LoanStatus.Confirmed, "ChainBreak::resolveLoanCircuit: bad loan status");

            _loan.closedAmount += amount;
            if (_loan.closedAmount == _loan.amount) {
                _loan.status = LoanStatus.Closed;
                _loan.closedAt = uint32(block.timestamp);
            }

            users[borrower].loans[lender] = _loan;
            emit LoanFill(borrower, lender, _loan);
        }
    }
}
