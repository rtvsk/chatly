import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { User } from 'src/users/user.entity';
import { Repository } from 'typeorm';
import { FriendshipStatus } from './enums/friendship-status.enum';
import { Friendship } from './friendship.entity';

@Injectable()
export class FriendsService {
  constructor(
    @InjectRepository(Friendship)
    private readonly friendshipsRepository: Repository<Friendship>,

    @InjectRepository(User)
    private readonly usersRepository: Repository<User>,
  ) {}

  async sendRequest(requesterId: string, receiverId: string) {
    if (requesterId === receiverId) {
      throw new BadRequestException('You cannot add yourself');
    }

    const receiver = await this.usersRepository.findOne({
      where: { id: receiverId },
    });

    if (!receiver) {
      throw new NotFoundException('User not found');
    }

    const existing = await this.friendshipsRepository.findOne({
      where: [
        { requesterId, receiverId },
        { requesterId: receiverId, receiverId: requesterId },
      ],
    });

    if (existing) {
      throw new BadRequestException('Friend request already exists');
    }

    const friendship = this.friendshipsRepository.create({
      requesterId,
      receiverId,
      status: FriendshipStatus.PENDING,
    });

    return this.friendshipsRepository.save(friendship);
  }

  async acceptRequest(userId: string, friendshipId: string) {
    const friendship = await this.friendshipsRepository.findOne({
      where: {
        id: friendshipId,
        receiverId: userId,
        status: FriendshipStatus.PENDING,
      },
    });

    if (!friendship) {
      throw new NotFoundException('Friend request not found');
    }

    friendship.status = FriendshipStatus.ACCEPTED;

    return this.friendshipsRepository.save(friendship);
  }

  async getMyFriends(userId: string) {
    const friendships = await this.friendshipsRepository.find({
      where: [
        { requesterId: userId, status: FriendshipStatus.ACCEPTED },
        { receiverId: userId, status: FriendshipStatus.ACCEPTED },
      ],
      relations: {
        requester: true,
        receiver: true,
      },
    });

    return friendships.map((friendship) => {
      const friend =
        friendship.requesterId === userId
          ? friendship.receiver
          : friendship.requester;

      return {
        id: friend.id,
        login: friend.login,
      };
    });
  }
}
