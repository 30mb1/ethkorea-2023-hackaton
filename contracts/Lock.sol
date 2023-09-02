// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract ChainBreak {
    enum LoanStatus {Pending, Confirmed, Closed}

    struct Loan {
        uint amount;
        uint closeAmount;
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

    address[] usersIndex;
    mapping (address => User) users;

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

    function getLoan(address lender, uint amount, uint32 ttl, string calldata description) external {}

    function giveLoan(address borrower, uint amount, uint32 ttl, string calldata description) external {}

    function confirmLoan(address lender) external {}
}
