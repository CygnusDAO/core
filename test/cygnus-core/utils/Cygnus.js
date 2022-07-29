const { keccak256 } = require('@ethersproject/keccak256');
const { toUtf8Bytes } = require('@ethersproject/strings');
const { AbiCoder } = require('@ethersproject/abi');
const { hexlify } = require('@ethersproject/bytes');
const { ecsign } = require('ethereumjs-util');

const hre = require('hardhat');
const chai = require('chai');
const { solidity } = require('ethereum-waffle');
chai.use(solidity);

const ethers = require('ethers');

function encode(types, values) {
  return ethers.utils.defaultAbiCoder.encode(types, values);
}

function encodePacked(types, values) {
  return ethers.utils.solidityPack(types, values);
}

function getDomainSeparator(name, token) {
  return keccak256(
    encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes('1')),
        // Local chainId
        31337,
        token,
      ],
    ),
  );
}

// GetApproval
async function getApprovalSignature(name, token, approve, nonce, deadline) {
  const DOMAIN_SEPARATOR = getDomainSeparator(name, token);

  const PERMIT_TYPEHASH = keccak256(
    toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
  );

  return keccak256(
    encodePacked(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
        keccak256(
          encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
            [
              PERMIT_TYPEHASH,
              approve.owner,
              approve.spender,
              approve.value.toString(),
              nonce.toString(),
              deadline.toString(),
            ],
          ),
        ),
      ],
    ),
  );
}

async function selfPermit(opts) {
  const { token, owner, spender, value, deadline, private_key } = opts;

  const name = await token.name();

  const nonce = await token.nonces(owner);

  const digest = await getApprovalSignature(name, token.address, { owner, spender, value }, nonce, deadline);

  const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), Buffer.from(private_key, 'hex'));

  return token.permit(owner, spender, value, deadline, v, hexlify(r), hexlify(s));
}

module.exports = {
  getDomainSeparator,
  getApprovalSignature,
  selfPermit,
};
